#!/usr/bin/env node
/**
 * DESIGN.md lint gate step: runs Google's DESIGN.md linter (`@google/design.md`, pinned in the root package.json)
 * and fails on any error or warning (its own CLI fails on errors only). Info findings are printed, never fatal.
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { lint } from '@google/design.md/linter';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const file = process.argv[2] ?? 'DESIGN.md';
const report = lint(readFileSync(resolve(root, file), 'utf8'));

const fatal = report.findings.filter(({ severity }) => severity === 'error' || severity === 'warning');
for (const { severity, path, message } of report.findings) {
  const where = path ? ` (${path})` : '';
  (severity === 'info' ? console.log : console.error)(`${severity}: ${message}${where}`);
}
if (fatal.length > 0) {
  console.error(`${file}: ${fatal.length} lint error(s) or warning(s); both fail the gate.`);
  process.exit(1);
}
const { infos = 0 } = report.summary ?? {};
console.log(`${file} passes the DESIGN.md linter (0 errors, 0 warnings, ${infos} infos).`);
