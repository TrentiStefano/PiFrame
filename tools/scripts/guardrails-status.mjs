#!/usr/bin/env node
/**
 * Prints how far the committed guardrail baselines are from zero, in total and per package
 * (`pnpm run guardrails:status`). It is a report, not a gate step: it always exits 0. The decision logic lives in
 * tools/guardrails/src/status.mjs.
 *
 *   node tools/scripts/guardrails-status.mjs
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { BOUNDARY_CONFIG_PATH, guardrailsStatus } from '../guardrails/src/index.mjs';
import { REPO } from './repo-files.mjs';

const read = (rel) => JSON.parse(fs.readFileSync(path.join(REPO, rel), 'utf8'));
const escapeHatch = read('tools/guardrails/escape-hatch-baseline.json');
const boundary = read(BOUNDARY_CONFIG_PATH).baseline ?? [];
const diagnostics = read('tools/guardrails/diagnostics-baseline.json');

const { allClear, totals, packages } = guardrailsStatus({ escapeHatch, boundary, diagnostics });

console.log('Guardrail baselines (progress toward zero; a report, not a gate):\n');
console.log(`  escape hatches     ${totals.escapeHatch}`);
console.log(`  import boundaries  ${totals.boundary}`);
console.log(`  diagnostics        ${totals.diagnostics}`);
console.log(`  total              ${totals.all}\n`);

const width = Math.max('package'.length, ...packages.map((p) => p.name.length));
console.log(`  ${'package'.padEnd(width)}  escape  boundary  diagnostics  total  status`);
for (const p of packages) {
  console.log(
    `  ${p.name.padEnd(width)}  ${String(p.escapeHatch).padStart(6)}  ${String(p.boundary).padStart(8)}  ` +
      `${String(p.diagnostics).padStart(11)}  ${String(p.total).padStart(5)}  ${p.done ? 'done' : 'open'}`
  );
}
console.log(allClear ? '\nAll clear: every baseline is zero.' : '');
