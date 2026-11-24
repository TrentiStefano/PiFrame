#!/usr/bin/env node
/**
 * The Dart analysis step (`check`, `verify` and CI run it). Runs `dart analyze --format=machine` in every Dart and
 * Flutter project (tools/scripts/flutter-projects.json), and fails when the diagnostics ratchet finds a count that
 * differs from the committed baseline (tools/guardrails/diagnostics-baseline.json). The decision logic and the output
 * parser live in tools/guardrails/src/diagnostics.mjs. See docs/pr-verification.md ("Diagnostics ratchet").
 *
 *   node tools/scripts/lint-flutter.mjs
 */
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { checkDiagnostics, DIAGNOSTICS_BASELINE_PATH, parseDartAnalyzeMachine } from '../guardrails/src/index.mjs';
import { REPO } from './repo-files.mjs';

const projects = JSON.parse(fs.readFileSync(path.join(REPO, 'tools/scripts/flutter-projects.json'), 'utf8'));
const baseline = JSON.parse(fs.readFileSync(path.join(REPO, DIAGNOSTICS_BASELINE_PATH), 'utf8'));

/** Files this branch changes (working tree and untracked included) since the baseline was last committed. */
function changedFiles() {
  const git = (...args) => {
    const result = spawnSync('git', args, { cwd: REPO, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
    return result.status === 0 ? result.stdout.split(/[\0\n]/).filter(Boolean) : [];
  };
  const since = git('log', '-1', '--format=%H', '--', DIAGNOSTICS_BASELINE_PATH)[0] ?? 'HEAD';
  return [...git('diff', '--name-only', '-z', since), ...git('ls-files', '-z', '--others', '--exclude-standard')];
}

/** The analyzer reports absolute paths: the repository-relative, `/`-separated form the ratchet and git use. */
const repoPath = (dir, file) =>
  path
    .relative(REPO, path.resolve(REPO, dir, file))
    .split(path.sep)
    .join('/');

const diagnostics = [];
for (const dir of projects) {
  console.log(`Running 'dart analyze' in ${dir}...`);
  const res = spawnSync('dart', ['analyze', '--format=machine'], {
    cwd: path.join(REPO, dir),
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    // dart is a .bat shim on Windows, so it needs the shell there.
    shell: process.platform === 'win32'
  });
  // The analyzer exits 0 with no issues, then 1, 2 and 3 for infos, warnings and errors (the findings are the data
  // the ratchet judges, not a failure of the step). Any other status means the analyzer did not run.
  if (res.error || ![0, 1, 2, 3].includes(res.status)) {
    console.error(`✖ dart analyze failed in ${dir} (exit ${res.status}).\n${res.stderr || res.error?.message || ''}`);
    process.exit(1);
  }
  for (const d of parseDartAnalyzeMachine(res.stdout, { package: dir })) {
    diagnostics.push({ ...d, file: repoPath(dir, d.file) });
  }
}

// The baseline file is shared with the TypeScript step: this step judges the Dart analyzer only.
const { ok, problems } = checkDiagnostics({
  diagnostics,
  baseline: { 'dart-analyze': baseline['dart-analyze'] ?? {} },
  changedFiles: changedFiles()
});
for (const dir of projects) {
  const mine = diagnostics.filter((d) => d.package === dir);
  const count = (severity) => mine.filter((d) => d.severity === severity).length;
  console.log(
    `  ${dir}: ${mine.length} diagnostics (${count('ERROR')} errors, ${count('WARNING')} warnings, ${count('INFO')} infos)`
  );
}
if (ok) {
  console.log(`✔ Dart analysis: ${diagnostics.length} diagnostics, every count matches ${DIAGNOSTICS_BASELINE_PATH}.`);
} else {
  console.error(`\n✖ Dart analysis: ${problems.length} count(s) differ from ${DIAGNOSTICS_BASELINE_PATH}:\n`);
  for (const p of problems) console.error(`- ${p.message}\n`);
  process.exit(1);
}
