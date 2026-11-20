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
 * Staleness: commit dates are written by whoever commits, so they are never used. The latest push time is a time
 * GitHub records: the creation time of this run when it was triggered by a push (opened, synchronize, reopened),
 * otherwise the creation time of the newest `ci.yml` pull-request run for the head commit (ci.yml runs on exactly
 * those events). When neither is known, any label counts as stale. A stale label is also removed, so approving
 * again is one click.
 */
import { spawnSync } from 'node:child_process';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { approvalStatus, APPROVAL_LABEL, APPROVAL_MARKER, BASELINE_PATH } from '../guardrails/src/index.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const PUSH_ACTIONS = new Set(['opened', 'synchronize', 'reopened']);
const NOT_NEEDED_ANY_MORE = `${APPROVAL_MARKER}\n**Guardrail approval: not needed.** Nothing in this pull request loosens a guardrail any more.`;

function git(...args) {
  const result = spawnSync('git', args, { cwd: REPO, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${result.stderr.trim()}`);
  return result.stdout;
}

function baselineAt(rev) {
  try {
    return JSON.parse(git('show', `${rev}:${BASELINE_PATH}`));
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

let labelEvents = [];
let latestPushAt = null;
const repo = `/repos/${env.GITHUB_REPOSITORY}`;
if (ci) {
  const events = await paged(`${repo}/issues/${env.PR_NUMBER}/events`);
  labelEvents = events
    .filter((e) => (e.event === 'labeled' || e.event === 'unlabeled') && e.label?.name)
    .map((e) => ({ action: e.event, label: e.label.name, at: e.created_at, actor: e.actor?.login }));

  const times = [];
  if (PUSH_ACTIONS.has(env.EVENT_ACTION)) {
    times.push((await api('GET', `${repo}/actions/runs/${env.GITHUB_RUN_ID}`)).created_at);
  }
  try {
    const runs = await paged(`${repo}/actions/workflows/ci.yml/runs?event=pull_request&head_sha=${env.HEAD_SHA}`);
    times.push(...runs.map((r) => r.created_at));
  } catch (err) {
    console.warn(`! could not list ci.yml runs (${err.message}); using this run's time only.`);
  }
  latestPushAt = times.filter(Boolean).sort().at(-1) ?? null;
}

const result = approvalStatus({ baseBaseline, headBaseline, changedPaths, labelEvents, latestPushAt });
console.log(`Guardrail approval: ${result.status}${result.stale ? ' (stale label)' : ''}`);
console.log(
  `  compared ${headRev} with merge base ${mergeBase.slice(0, 12)}; latest push: ${latestPushAt ?? 'unknown'}`
);
for (const reason of result.reasons) console.log(`  - ${reason}`);
if (result.comment) console.log(`\n${result.comment}\n`);

if (ci) {
  // A fork PR's token is read-only: the verdict (this job's exit code) still holds, only the comment is skipped.
  try {
    const comments = await paged(`${repo}/issues/${env.PR_NUMBER}/comments`);
    const mine = comments.find((c) => c.user?.type === 'Bot' && c.body?.startsWith(APPROVAL_MARKER));
    const body = result.comment ?? (mine ? NOT_NEEDED_ANY_MORE : null);
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
