#!/usr/bin/env node
/**
 * DESIGN.md lint gate step: runs Google's DESIGN.md linter (`@google/design.md`, pinned in the root package.json)
 * and fails on any error or warning (its own CLI fails on errors only). Info findings are printed, never fatal.
 * See docs/pr-verification.md.
 *
 *   node tools/scripts/lint-design.mjs [file]
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { lint } from '@google/design.md/linter';
import { REPO } from './repo-files.mjs';

const file = process.argv[2] ?? 'DESIGN.md';
const report = lint(readFileSync(resolve(REPO, file), 'utf8'));

const fatal = report.findings.filter(({ severity }) => severity === 'error' || severity === 'warning');
const describe = ({ severity, path, message }) => `${severity}: ${message}${path ? ` (${path})` : ''}`;
const { infos = 0 } = report.summary ?? {};
if (fatal.length === 0) {
  console.log(`✔ design lint: ${file} passes the DESIGN.md linter (0 errors, 0 warnings, ${infos} infos).`);
  for (const finding of report.findings) console.log(`  ${describe(finding)}`);
} else {
  console.error(`\n✖ design lint: ${fatal.length} error(s) or warning(s) in ${file}; both fail the gate:\n`);
  for (const finding of fatal) console.error(`- ${describe(finding)}`);
  console.error(
    `\nTo fix it, edit ${file} where each finding points (the path is the front-matter token or section). ` +
      'Run `node tools/scripts/lint-design.mjs` again to confirm.'
  );
  process.exit(1);
}
