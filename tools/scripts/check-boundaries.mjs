#!/usr/bin/env node
/**
 * The import-boundary check (`check`, `verify` and CI run it). Reads the repository's Dart and TypeScript sources
 * (tracked plus untracked, not ignored, as they are on disk) and the committed config (tools/guardrails/boundary.json:
 * the daemon allowed-dependency table and the baseline), and fails on any import the rules forbid that the baseline
 * does not accept, and on any baseline entry that no longer matches. The rules live in
 * tools/guardrails/src/boundary.mjs. See docs/pr-verification.md ("Import boundaries").
 *
 *   node tools/scripts/check-boundaries.mjs
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { BOUNDARY_CONFIG_PATH, checkBoundaries, DART_FILE, toPosix } from '../guardrails/src/index.mjs';
import { REPO, repoFiles } from './repo-files.mjs';

const SCOPE = /^(apps\/pi_frame\/lib\/|apps\/agentd\/src\/|packages\/)/;
const isSource = (p) => DART_FILE.test(p) || (p.endsWith('.ts') && !p.endsWith('.d.ts'));

const listed = repoFiles();
if (!listed) {
  console.error('✖ import boundaries: `git ls-files` failed; run it inside the repository.');
  process.exit(1);
}
const config = JSON.parse(fs.readFileSync(path.join(REPO, BOUNDARY_CONFIG_PATH), 'utf8'));
const files = listed
  .map(toPosix)
  .filter((p) => SCOPE.test(p) && isSource(p))
  .map((p) => ({ path: p, contents: fs.readFileSync(path.join(REPO, p), 'utf8') }));

const { ok, problems } = checkBoundaries({
  files,
  daemonAllowedDependencies: config.daemonAllowedDependencies,
  baseline: config.baseline
});
if (ok) {
  console.log(
    `✔ import boundaries: ${files.length} source files follow the layer rules, the daemon table and the baseline.`
  );
} else {
  console.error(`\n✖ import boundaries: ${problems.length} problem(s):\n`);
  for (const p of problems) console.error(`- [${p.rule}] ${p.message}\n`);
  process.exit(1);
}
