#!/usr/bin/env node
/**
 * Guardrail approval (`.github/workflows/guardrails-approval.yml` runs it on every pull-request event). Reads the
 * escape-hatch baselines and changed paths from git and the PR's label events and push time from GitHub, asks
 * `approvalStatus` (tools/guardrails/src/approval.mjs) for the verdict, keeps one PR comment in sync with it, and
 * exits 1 while approval is needed. See docs/pr-verification.md#guardrail-approval.
 *
 * In CI (environment from the workflow):
 *   GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_API_URL, GITHUB_RUN_ID, PR_NUMBER, BASE_SHA, HEAD_SHA, EVENT_ACTION
 *
 * Locally (no GitHub access, no labels: prints the verdict and the comment it would post):
 *   node tools/scripts/guardrails-approval.mjs --base origin/main --head HEAD
 *
 * Staleness: this script reads the times GitHub recorded (this run's creation time and the head commit's `ci.yml`
 * pull-request runs) and `approvalStatus` picks the latest push from them. A stale label is also removed, so
 * approving again is one click.
 */
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  approvalStatus,
  APPROVAL_LABEL,
  APPROVAL_MARKER,
  BASELINE_PATH,
  DIAGNOSTICS_BASELINE_PATH
} from '../guardrails/src/index.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

function git(...args) {
  const result = spawnSync('git', args, { cwd: REPO, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${result.stderr.trim()}`);
  return result.stdout;
}

function baselineAt(rev, file = BASELINE_PATH) {
  try {
    return JSON.parse(git('show', `${rev}:${file}`));
  } catch {
    return {}; // no baseline at that commit: every count on the other side is new
  }
}

function argValue(name) {
  const i = process.argv.indexOf(name);
  return i === -1 ? undefined : process.argv[i + 1];
}

const env = process.env;
const ci = Boolean(env.GITHUB_TOKEN && env.PR_NUMBER);
const baseRev = ci ? env.BASE_SHA : (argValue('--base') ?? 'origin/main');
const headRev = ci ? env.HEAD_SHA : (argValue('--head') ?? 'HEAD');

// What the PR changes, as GitHub's "Files changed" tab shows it: the head against its merge base with the base.
const mergeBase = git('merge-base', baseRev, headRev).trim();
const changedPaths = git('diff', '--name-only', '--no-renames', '-z', mergeBase, headRev).split('\0').filter(Boolean);
const baseBaseline = baselineAt(mergeBase);
const headBaseline = baselineAt(headRev);
const diagnosticsBaseBaseline = baselineAt(mergeBase, DIAGNOSTICS_BASELINE_PATH);
const diagnosticsHeadBaseline = baselineAt(headRev, DIAGNOSTICS_BASELINE_PATH);

const api = async (method, route, body) => {
  const res = await fetch(`${env.GITHUB_API_URL || 'https://api.github.com'}${route}`, {
    method,
    headers: {
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      accept: 'application/vnd.github+json',
      'x-github-api-version': '2022-11-28',
      ...(body ? { 'content-type': 'application/json' } : {})
    },
    body: body ? JSON.stringify(body) : undefined
  });
  if (!res.ok) throw new Error(`${method} ${route}: HTTP ${res.status} ${(await res.text()).slice(0, 300)}`);
  return res.status === 204 ? null : res.json();
};
const paged = async (route) => {
  const out = [];
  for (let page = 1; ; page += 1) {
    const sep = route.includes('?') ? '&' : '?';
    const items = await api('GET', `${route}${sep}per_page=100&page=${page}`);
    const list = Array.isArray(items) ? items : (items.workflow_runs ?? []);
    out.push(...list);
    if (list.length < 100) return out;
  }
};

/** Reads a GitHub value that only sharpens the verdict; on failure warns and returns the fallback. */
const tryRead = async (what, read, fallback) => {
  try {
    return await read();
  } catch (err) {
    console.warn(`! could not read ${what} (${err.message}).`);
    return fallback;
  }
};

let labelEvents = [];
let runCreatedAt;
let ciRunTimes = [];
let mine;
const repo = `/repos/${env.GITHUB_REPOSITORY}`;
if (ci) {
  const events = await paged(`${repo}/issues/${env.PR_NUMBER}/events`);
  labelEvents = events
    .filter((e) => (e.event === 'labeled' || e.event === 'unlabeled') && e.label?.name)
    .map((e) => ({ action: e.event, label: e.label.name, at: e.created_at, actor: e.actor?.login }));
  runCreatedAt = await tryRead(
    "this run's creation time",
    async () => (await api('GET', `${repo}/actions/runs/${env.GITHUB_RUN_ID}`)).created_at,
    undefined
  );
  ciRunTimes = await tryRead(
    'the ci.yml runs',
    async () =>
      (await paged(`${repo}/actions/workflows/ci.yml/runs?event=pull_request&head_sha=${env.HEAD_SHA}`)).map(
        (r) => r.created_at
      ),
    []
  );
  const comments = await tryRead('the PR comments', () => paged(`${repo}/issues/${env.PR_NUMBER}/comments`), []);
  mine = comments.find((comment) => comment.user?.type === 'Bot' && comment.body?.startsWith(APPROVAL_MARKER));
}

const result = approvalStatus({
  baseBaseline,
  headBaseline,
  diagnosticsBaseBaseline,
  diagnosticsHeadBaseline,
  changedPaths,
  labelEvents,
  eventAction: env.EVENT_ACTION,
  runCreatedAt,
  ciRunTimes,
  previousComment: mine?.body ?? null,
  // A link to the file's diff in the PR's "Files changed" view; only known in CI (the PR number is set there).
  goldenFileLink: ci
    ? (file) =>
        `https://github.com/${env.GITHUB_REPOSITORY}/pull/${env.PR_NUMBER}/files#diff-${createHash('sha256').update(file).digest('hex')}`
    : undefined
});
const { latestPushAt } = result;
console.log(`Guardrail approval: ${result.status}${result.stale ? ' (stale label)' : ''}`);
console.log(
  `  compared ${headRev} with merge base ${mergeBase.slice(0, 12)}; latest push: ${latestPushAt ?? 'unknown'}`
);
for (const reason of result.reasons) console.log(`  - ${reason}`);
if (result.comment) console.log(`\n${result.comment}\n`);

if (ci) {
  // A fork PR's token is read-only: the verdict (this job's exit code) still holds, only the comment is skipped.
  try {
    const body = result.comment;
    if (body && mine && mine.body !== body) await api('PATCH', `${repo}/issues/comments/${mine.id}`, { body });
    if (body && !mine) await api('POST', `${repo}/issues/${env.PR_NUMBER}/comments`, { body });
    if (result.stale && latestPushAt) {
      await api('DELETE', `${repo}/issues/${env.PR_NUMBER}/labels/${encodeURIComponent(APPROVAL_LABEL)}`);
      console.log(`Removed the stale ${APPROVAL_LABEL} label.`);
    }
  } catch (err) {
    console.warn(`! could not update the PR comment or labels (${err.message}); the check result still applies.`);
  }
}

if (result.status === 'needed') {
  console.error(`✖ Guardrail approval needed: a human must add the ${APPROVAL_LABEL} label after reviewing.`);
  process.exit(1);
}
