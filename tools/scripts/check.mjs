#!/usr/bin/env node
/**
 * The fast inner-loop check. Runs the `check` tier of the shared step list (tools/guardrails/src/steps.mjs) in the
 * current working tree: no install, no worktree, no merge with origin/main.
 *
 *   pnpm run check                                         TypeScript type checking + flutter analyze
 *   pnpm run check -- apps/pi_frame/test/foo_test.dart     + that Flutter test
 *   pnpm run check -- tools/guardrails/test/x.test.mjs     + that Node test
 *   pnpm run check -- apps/agentd/src/pi/test/x.test.ts    + that TypeScript test, from apps/agentd/dist/.../x.test.js
 *
 * It also runs the Flutter tests whose imports reach a Dart file changed on this branch (since its merge base with
 * origin/main) or in the working tree, so a test that reaches a change only indirectly runs too (#116).
 *
 * Exit code 0 only when every step passed. `pnpm run verify` stays the full gate before a PR.
 * See docs/pr-verification.md.
 */
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { affectedDartTests, stepList, toPosix } from '../guardrails/src/index.mjs';
import { repoFiles } from './repo-files.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const IS_WIN = process.platform === 'win32';
// pnpm runs scripts from the repository root; INIT_CWD is where the command was typed, so relative paths work too.
const callerCwd = process.env.INIT_CWD || process.cwd();
const tests = process.argv
  .slice(2)
  .filter((arg) => arg !== '--')
  .map((arg) => path.relative(REPO, path.resolve(callerCwd, arg)));

const paint = (code, s) => (process.stdout.isTTY ? `\x1b[${code}m${s}\x1b[0m` : s);
const fail = (message) => {
  console.error(paint(31, `\n✖ ${message}`));
  process.exit(1);
};

const flutterProjects = JSON.parse(fs.readFileSync(path.join(REPO, 'tools/scripts/flutter-projects.json'), 'utf8'));

/** Lines of a git command's output, or an empty list when it fails (no origin/main, not a repository). */
const gitLines = (...args) => {
  const result = spawnSync('git', args, { cwd: REPO, encoding: 'utf8' });
  return result.status === 0 ? result.stdout.split(/\r?\n/).filter(Boolean) : [];
};

/** Per Flutter project, the test files whose imports reach a Dart file changed on this branch or in the tree. */
function affectedTests() {
  const base = gitLines('merge-base', 'HEAD', 'origin/main')[0] ?? 'HEAD';
  const changed = [...gitLines('diff', '--name-only', base), ...gitLines('ls-files', '--others', '--exclude-standard')];
  const projects = flutterProjects.map((dir) => ({
    dir,
    package: fs.readFileSync(path.join(REPO, dir, 'pubspec.yaml'), 'utf8').match(/^name:\s*(\S+)/m)?.[1] ?? ''
  }));
  const files = (repoFiles() ?? [])
    .map(toPosix)
    .filter((p) => p.endsWith('.dart') && flutterProjects.some((dir) => p.startsWith(`${dir}/`)))
    .map((p) => ({ path: p, contents: fs.readFileSync(path.join(REPO, p), 'utf8') }));
  return affectedDartTests({ files, projects, changed: changed.map(toPosix) });
}

let steps;
try {
  steps = stepList('check', { tests, flutterProjects, affected: affectedTests() });
} catch (err) {
  fail(err.message);
}
for (const file of tests) {
  if (!fs.existsSync(path.join(REPO, file))) fail(`check: test file "${file}" does not exist.`);
}

const started = Date.now();
let index = 0;
for (const { name, command, cwd } of steps) {
  index += 1;
  const [program, ...args] = command;
  // `node` steps run on this Node.js, without a shell; everything else goes through the shell on Windows (.cmd shims).
  const node = program === 'node';
  console.log(paint(1, `\n[${index}/${steps.length}] ${name}`));
  const t0 = Date.now();
  const result = spawnSync(node ? process.execPath : program, args, {
    cwd: path.join(REPO, cwd || '.'),
    stdio: 'inherit',
    shell: IS_WIN && !node
  });
  const secs = ((Date.now() - t0) / 1000).toFixed(1);
  if (result.status !== 0) fail(`Step failed: ${name} (${secs}s).`);
  console.log(paint(32, `ok`) + paint(2, ` (${secs}s)`));
}
console.log(
  paint(32, `\n✔ check: all ${steps.length} steps passed in ${((Date.now() - started) / 1000).toFixed(1)}s.`)
);
