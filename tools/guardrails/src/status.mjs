/**
 * Guardrail status: a report of how far the three committed baselines are from zero, in total and per package. It is
 * not a gate step: it never fails a check. A package is done when every baseline counts zero for it.
 *
 * Pure: no I/O. tools/scripts/guardrails-status.mjs reads the baselines and prints the result (`pnpm run guardrails:status`).
 */
import { PACKAGES } from './escape-hatches.mjs';

/**
 * The package a repository path belongs to: the audited package whose directory contains it (the escape-hatch names,
 * so `apps/agentd` is `agentd` and `tools/fake-pi` is `tools`), otherwise the path's first two segments.
 * @param {string} path a repository-relative path, or a package directory such as `apps/agentd`
 * @returns {string}
 */
export function packageOf(path) {
  const normalised = path.endsWith('/') ? path : `${path}/`;
  const entry = PACKAGES.find(([, dir]) => normalised.startsWith(dir));
  if (entry) return entry[0];
  return path.split('/').slice(0, 2).join('/');
}

/**
 * @param {object} input
 * @param {Record<string, Record<'lib' | 'test', Record<string, number>>>} input.escapeHatch the escape-hatch baseline
 * @param {{ file: string, import: string }[]} input.boundary the import-boundary baseline (one entry per violation)
 * @param {Record<string, Record<string, Record<string, number>>>} input.diagnostics the diagnostics baseline: tool → directory → rule → count
 * @returns {{
 *   allClear: boolean,
 *   totals: { escapeHatch: number, boundary: number, diagnostics: number, all: number },
 *   packages: { name: string, escapeHatch: number, boundary: number, diagnostics: number, total: number, done: boolean }[]
 * }}
 */
export function guardrailsStatus({ escapeHatch, boundary, diagnostics }) {
  const byPackage = new Map();
  const slot = (name) => {
    if (!byPackage.has(name)) byPackage.set(name, { escapeHatch: 0, boundary: 0, diagnostics: 0 });
    return byPackage.get(name);
  };

  for (const [pkg, kinds] of Object.entries(escapeHatch)) {
    for (const patterns of Object.values(kinds)) {
      for (const count of Object.values(patterns)) slot(pkg).escapeHatch += count;
    }
  }
  for (const entry of boundary) slot(packageOf(entry.file)).boundary += 1;
  for (const dirs of Object.values(diagnostics)) {
    for (const [dir, rules] of Object.entries(dirs)) {
      for (const count of Object.values(rules)) slot(packageOf(dir)).diagnostics += count;
    }
  }

  const packages = [...byPackage.entries()]
    .map(([name, counts]) => {
      const total = counts.escapeHatch + counts.boundary + counts.diagnostics;
      return { name, ...counts, total, done: total === 0 };
    })
    .sort((a, b) => a.name.localeCompare(b.name));

  const sum = (key) => packages.reduce((n, p) => n + p[key], 0);
  const totals = {
    escapeHatch: sum('escapeHatch'),
    boundary: sum('boundary'),
    diagnostics: sum('diagnostics'),
    all: sum('total')
  };
  return { allClear: totals.all === 0, totals, packages };
}
