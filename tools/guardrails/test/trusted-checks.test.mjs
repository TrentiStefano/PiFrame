import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// These workflows judge a pull request, so they must run the base branch's reviewed scripts. The pull request's
// head may be fetched as data, but never checked out: a checkout would let a PR run its own copy of the check (#93).
const TRUSTED_WORKFLOWS = ['.github/workflows/guardrails-approval.yml', '.github/workflows/pr-body.yml'];

for (const file of TRUSTED_WORKFLOWS) {
  test(`${file} never checks out the pull request's own code`, () => {
    const text = readFileSync(fileURLToPath(new URL(`../../../${file}`, import.meta.url)), 'utf8');
    assert.ok(text.includes('github.event.pull_request.base.sha'), `${file} must check out the base commit`);
    assert.doesNotMatch(text, /git\s+checkout\b/, `${file} switches to other code with git checkout`);
    assert.doesNotMatch(text, /ref:\s*\$\{\{\s*github\.event\.pull_request\.head/, `${file} checks out the PR head`);
  });
}
