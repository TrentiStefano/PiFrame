#!/usr/bin/env node
/**
 * Verify, then open a pull request to `main`.
 *
 *   pnpm run pr                       verify (CI + release validation), push the branch, open the PR
 *   pnpm run pr -- --release          also run the desktop/web builds of the release job
 *   pnpm run pr -- --e2e              also run the emulated-iPhone remote web test
 *   pnpm run pr -- --title "..." --body "..."   forwarded to `gh pr create`
 *
 * Flags understood by `verify` (--release, --e2e, --force, --no-merge, --verbose) are passed to it; every
 * other argument goes to `gh pr create`. A body is required: --body, or --body-file (`-` reads stdin), filled in from
 * .github/pull_request_template.md. The body is checked (tools/guardrails/src/pr-body.mjs) before anything else runs.
 * Nothing is pushed and no PR is created unless every verification step passed.
 * See docs/pr-verification.md.
 */
import { spawnSync, execFileSync } from 'node:child_process';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { buildPrCreateArgs, prBodyText, splitArgs } from './pr-args.mjs';
import { checkPrBody } from '../guardrails/src/index.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
// No shell anywhere: on Windows a shell re-splits arguments that contain spaces (e.g. --title "fix(ui): ...").
const { verifyArgs, ghArgs } = splitArgs(process.argv.slice(2));

function fail(message) {
  console.error(`\n✖ ${message}`);
  process.exit(1);
}

function out(cmd, cmdArgs) {
  return execFileSync(cmd, cmdArgs, { cwd: REPO, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

// 1. Preconditions that do not need the (slow) verification.
const branch = out('git', ['branch', '--show-current']);
if (!branch) fail('Detached HEAD: check out a branch first.');
if (branch === 'main') fail('You are on main. Create a feature branch, commit there, then run `pnpm run pr`.');

// The body is the review shape the maintainer reads (the PR template). Refused here, before any push or gh call.
const readBody = (file) => {
  try {
    return readFileSync(file === '-' ? 0 : file, 'utf8');
  } catch (err) {
    return fail(`Cannot read --body-file ${file}: ${err.message}`);
  }
};
const body = prBodyText(ghArgs, readBody);
if (body === undefined) {
  fail(
    'No pull request body. Pass --body "..." or --body-file <file> with the filled-in template (.github/pull_request_template.md). The commits are not used.'
  );
}
const bodyCheck = checkPrBody(body);
if (!bodyCheck.ok) {
  fail(
    [
      'The pull request body is incomplete, so no pull request was opened:',
      ...bodyCheck.problems.map((p) => `  - ${p}`)
    ].join('\n')
  );
}

try {
  out('gh', ['--version']);
} catch {
  fail(
    'GitHub CLI (gh) not found. Install it from https://cli.github.com and run `gh auth login`, or open the PR by hand after `pnpm run verify`.'
  );
}
try {
  out('gh', ['auth', 'status']);
} catch {
  fail('GitHub CLI is not authenticated. Run `gh auth login`.');
}

let existing = '';
try {
  existing = out('gh', ['pr', 'view', '--json', 'url,state', '--jq', 'select(.state=="OPEN") | .url']);
} catch {
  // no PR for this branch
}

// 2. Verification (HEAD merged with origin/main). Exits non-zero on failure -> nothing below runs.
console.log(`Verifying branch ${branch} before opening the pull request...\n`);
const verify = spawnSync(process.execPath, [path.join(REPO, 'tools/scripts/verify-ci.mjs'), ...verifyArgs], {
  cwd: REPO,
  stdio: 'inherit'
});
if (verify.status !== 0)
  fail('Verification failed: no push, no pull request. Fix the problem and run `pnpm run pr` again.');

// 3. Push and open the PR.
console.log(`\nPushing ${branch} ...`);
const push = spawnSync('git', ['push', '--set-upstream', 'origin', 'HEAD'], { cwd: REPO, stdio: 'inherit' });
if (push.status !== 0) fail('git push failed.');

if (existing) {
  console.log(`\n✔ A pull request is already open for this branch (updated by the push):\n  ${existing}`);
  process.exit(0);
}

const create = spawnSync('gh', buildPrCreateArgs(ghArgs), { cwd: REPO, stdio: 'inherit' });
if (create.status !== 0) fail('gh pr create failed.');
console.log('\n✔ Pull request opened from a verified branch.');
