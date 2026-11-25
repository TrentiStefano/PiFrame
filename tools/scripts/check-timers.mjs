#!/usr/bin/env node
/**
 * The named-timer check (`check`, `verify` and CI run it). Reads the app's Dart sources and the daemon's TypeScript
 * sources (tracked plus untracked, not ignored, as they are on disk) and fails on any timer whose duration is a
 * numeric literal: each delay must be a named constant next to its use. The rules live in
 * tools/guardrails/src/timers.mjs. See docs/pr-verification.md ("Named timers").
 *
 *   node tools/scripts/check-timers.mjs
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { checkTimers, DART_FILE, SCRIPT_FILE, toPosix } from '../guardrails/src/index.mjs';
import { REPO, repoFiles } from './repo-files.mjs';

const SCOPE = /^(apps\/pi_frame\/lib\/|apps\/agentd\/src\/)/;
const isSource = (p) => DART_FILE.test(p) || (SCRIPT_FILE.test(p) && !p.endsWith('.d.ts'));

const listed = repoFiles();
if (!listed) {
  console.error('✖ named timers: `git ls-files` failed; run it inside the repository.');
  process.exit(1);
}
const files = listed
  .map(toPosix)
  .filter((p) => SCOPE.test(p) && isSource(p))
  .map((p) => ({ path: p, contents: fs.readFileSync(path.join(REPO, p), 'utf8') }));

const { ok, problems } = checkTimers({ files });
if (ok) {
  console.log(`✔ named timers: ${files.length} source files; every timer duration is a named constant or variable.`);
} else {
  console.error(`\n✖ named timers: ${problems.length} literal timer duration(s):\n`);
  for (const p of problems) console.error(`- ${p.path}:${p.line} [${p.rule}] ${p.message}\n`);
  process.exit(1);
}
