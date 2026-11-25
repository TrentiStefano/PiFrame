#!/usr/bin/env node
/**
 * PR-body check adapter: reads a pull request body and asks `checkPrBody` (tools/guardrails/src/pr-body.mjs) for the
 * verdict. Exits 1 and names each missing part when the body is incomplete. See docs/pr-verification.md#pr-body-check.
 *
 *   node tools/scripts/check-pr-body.mjs --file body.md     a body on disk
 *   node tools/scripts/check-pr-body.mjs --pr 81            the body of a pull request, read with `gh` (GH_TOKEN, GH_REPO)
 *
 * `.github/workflows/pr-body.yml` runs it with `--pr` on every pull-request event; `pnpm run pr` checks the body it is
 * given before it creates the pull request, through the same checkPrBody.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { checkPrBody } from '../guardrails/src/index.mjs';

function argValue(name) {
  const i = process.argv.indexOf(name);
  return i === -1 ? undefined : process.argv[i + 1];
}

function bodyOfPullRequest(number) {
  // The body text is data: it is checked, never run.
  return execFileSync('gh', ['pr', 'view', number, '--json', 'body', '--jq', '.body'], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'inherit']
  });
}

const file = argValue('--file');
const pr = argValue('--pr');
if (!file === !pr) {
  console.error('Usage: check-pr-body.mjs (--file <body.md> | --pr <number>)');
  process.exit(2);
}

const body = file ? readFileSync(file, 'utf8') : bodyOfPullRequest(pr);
const { ok, problems } = checkPrBody(body);
if (ok) {
  console.log('✔ The pull request body has the review shape the template asks for.');
  process.exit(0);
}
console.error('✖ The pull request body is incomplete:');
for (const problem of problems) console.error(`  - ${problem}`);
console.error('Fill in .github/pull_request_template.md (every section) and check again.');
process.exit(1);
