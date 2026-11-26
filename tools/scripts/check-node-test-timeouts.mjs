#!/usr/bin/env node
/**
 * The Node test timeout check (`check`, `verify` and CI run it). Collects every `node --test` command: the `scripts`
 * of each tracked package.json, the gate's own steps and the CI workflow's `run:` lines, and fails on any that has no
 * `--test-timeout`. The rule lives in tools/guardrails/src/node-test-timeouts.mjs. See docs/pr-verification.md
 * ("Node test timeouts").
 *
 *   node tools/scripts/check-node-test-timeouts.mjs
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { checkNodeTestTimeouts, stepList, toPosix } from '../guardrails/src/index.mjs';
import { REPO, repoFiles } from './repo-files.mjs';

const WORKFLOW = '.github/workflows/ci.yml';

const listed = repoFiles();
if (!listed) {
  console.error('✖ node test timeouts: `git ls-files` failed; run it inside the repository.');
  process.exit(1);
}

const commands = [];
for (const file of listed.map(toPosix)) {
  if (path.posix.basename(file) !== 'package.json' || file.split('/').includes('node_modules')) continue;
  const { scripts = {} } = JSON.parse(fs.readFileSync(path.join(REPO, file), 'utf8'));
  for (const [name, command] of Object.entries(scripts)) commands.push({ path: file, name, command: String(command) });
}
for (const tier of ['check', 'verify']) {
  for (const step of stepList(tier)) {
    commands.push({ path: 'tools/guardrails/src/steps.mjs', name: step.name, command: step.command.join(' ') });
  }
}
fs.readFileSync(path.join(REPO, WORKFLOW), 'utf8')
  .split(/\r?\n/)
  .forEach((line, index) => {
    const run = line.match(/^\s*(?:-\s*)?run:\s*(.+)$/);
    if (run) commands.push({ path: WORKFLOW, name: `line ${index + 1}`, command: run[1] });
  });

const { ok, problems } = checkNodeTestTimeouts({ commands });
if (ok) {
  console.log(`✔ node test timeouts: ${commands.length} commands; every node --test run has a --test-timeout.`);
} else {
  console.error(`\n✖ node test timeouts: ${problems.length} node --test command(s) without a timeout:\n`);
  for (const p of problems) console.error(`- ${p.path} (${p.name}): ${p.message}\n`);
  process.exit(1);
}
