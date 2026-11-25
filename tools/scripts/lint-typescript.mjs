#!/usr/bin/env node
/**
 * The TypeScript analysis step (`check`, `verify` and CI run it). Runs `tsc --noEmit` in every TypeScript package
 * (tools/scripts/typescript-projects.json) and ESLint once over all of them, then fails when the diagnostics ratchet
 * finds a count that differs from the committed baseline (tools/guardrails/diagnostics-baseline.json). The compiler
 * flags are in tsconfig.base.json; the ESLint rules in eslint.config.mjs. The parsers live in
 * tools/guardrails/src/diagnostics.mjs. See docs/pr-verification.md ("Diagnostics ratchet").
 *
 *   node tools/scripts/lint-typescript.mjs
 */
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import {
  checkDiagnostics,
  DIAGNOSTICS_BASELINE_PATH,
  parseEslintJson,
  parseTscOutput
} from '../guardrails/src/index.mjs';
import { changedFiles, REPO } from './repo-files.mjs';

const TOOLS = ['tsc', 'eslint'];
const packages = JSON.parse(fs.readFileSync(path.join(REPO, 'tools/scripts/typescript-projects.json'), 'utf8'));
const baseline = JSON.parse(fs.readFileSync(path.join(REPO, DIAGNOSTICS_BASELINE_PATH), 'utf8'));
// The baseline file is shared with the Dart step: this step judges its own tools only.
const ownBaseline = Object.fromEntries(TOOLS.map((tool) => [tool, baseline[tool] ?? {}]));

/** Runs a Node script from node_modules; `tsc` and `eslint` exit 1 or 2 on findings, which the ratchet judges. */
function runNodeTool(cwd, script, args, label) {
  const res = spawnSync(process.execPath, [script, ...args], {
    cwd,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024
  });
  if (res.error || res.status === null || res.status > 2) {
    console.error(`✖ ${label} did not run (exit ${res.status}).\n${res.stderr || res.error?.message || ''}`);
    process.exit(1);
  }
  return res.stdout;
}

const tscBin = path.join(REPO, 'node_modules/typescript/bin/tsc');
const eslintBin = path.join(REPO, 'node_modules/eslint/bin/eslint.js');

const diagnostics = [];
for (const dir of packages) {
  console.log(`Running 'tsc --noEmit' in ${dir}...`);
  const stdout = runNodeTool(
    path.join(REPO, dir),
    tscBin,
    ['--noEmit', '-p', 'tsconfig.json', '--pretty', 'false'],
    `tsc in ${dir}`
  );
  for (const d of parseTscOutput(stdout, { package: dir })) {
    diagnostics.push({ ...d, file: `${dir}/${d.file}` });
  }
}

console.log(`Running ESLint over ${packages.length} TypeScript packages...`);
const srcDirs = packages.map((dir) => `${dir}/src`);
const eslintOut = runNodeTool(REPO, eslintBin, ['--format', 'json', ...srcDirs], 'ESLint');
diagnostics.push(...parseEslintJson(eslintOut, { repoRoot: REPO, packages }));

const { ok, problems } = checkDiagnostics({ diagnostics, baseline: ownBaseline, changedFiles: changedFiles() });
for (const tool of TOOLS) {
  for (const dir of packages) {
    const mine = diagnostics.filter((d) => d.tool === tool && d.package === dir);
    console.log(`  ${tool} ${dir}: ${mine.length} diagnostics`);
  }
}
if (ok) {
  const total = diagnostics.length;
  console.log(`✔ TypeScript analysis: ${total} diagnostics, every count matches ${DIAGNOSTICS_BASELINE_PATH}.`);
} else {
  console.error(`\n✖ TypeScript analysis: ${problems.length} count(s) differ from ${DIAGNOSTICS_BASELINE_PATH}:\n`);
  for (const p of problems) console.error(`- ${p.message}\n`);
  process.exit(1);
}
