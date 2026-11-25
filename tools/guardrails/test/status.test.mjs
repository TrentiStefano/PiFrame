import test from 'node:test';
import assert from 'node:assert/strict';
import { guardrailsStatus } from '../src/status.mjs';

/** An escape-hatch baseline for the given `[package, kind, pattern, count]` entries, every other count zero. */
function escapeHatch(...entries) {
  const b = {};
  for (const [pkg, kind, pattern, count] of entries) {
    b[pkg] ??= { lib: {}, test: {} };
    b[pkg][kind][pattern] = count;
  }
  return b;
}

/** A diagnostics baseline for the given `[tool, directory, rule, count]` entries. */
function diagnostics(...entries) {
  const b = {};
  for (const [tool, dir, rule, count] of entries) {
    b[tool] ??= {};
    b[tool][dir] ??= {};
    b[tool][dir][rule] = count;
  }
  return b;
}

test('all-zero baselines read all clear and every package is done', () => {
  const status = guardrailsStatus({
    escapeHatch: escapeHatch(['agentd', 'lib', 'as any', 0], ['pcp-ts', 'test', ': any', 0]),
    boundary: [],
    diagnostics: diagnostics(['tsc', 'apps/agentd', 'TS2322', 0])
  });
  assert.equal(status.allClear, true);
  assert.equal(status.totals.all, 0);
  assert.ok(status.packages.every((p) => p.done && p.total === 0));
});

test('totals are summed per baseline', () => {
  const status = guardrailsStatus({
    escapeHatch: escapeHatch(['agentd', 'lib', 'as any', 3], ['agentd', 'test', ': any', 2]),
    boundary: [
      { file: 'apps/agentd/src/pi/a.ts', import: '../server/b' },
      { file: 'apps/pi_frame/lib/domain/c.dart', import: 'package:flutter/material.dart' }
    ],
    diagnostics: diagnostics(
      ['dart-analyze', 'apps/pi_frame', 'discarded_futures', 4],
      ['tsc', 'apps/agentd', 'TS2322', 1]
    )
  });
  assert.deepEqual(status.totals, { escapeHatch: 5, boundary: 2, diagnostics: 5, all: 12 });
  assert.equal(status.allClear, false);
});

test('each package sums all three baselines and marks itself done only at zero', () => {
  const status = guardrailsStatus({
    escapeHatch: escapeHatch(['agentd', 'lib', 'as any', 3], ['pcp-ts', 'lib', 'as any', 0]),
    boundary: [{ file: 'apps/agentd/src/pi/a.ts', import: '../server/b' }],
    diagnostics: diagnostics(['tsc', 'apps/agentd', 'TS2322', 1], ['eslint', 'packages/pcp-ts', 'x', 0])
  });
  const byName = Object.fromEntries(status.packages.map((p) => [p.name, p]));
  assert.deepEqual(
    {
      escapeHatch: byName.agentd.escapeHatch,
      boundary: byName.agentd.boundary,
      diagnostics: byName.agentd.diagnostics
    },
    { escapeHatch: 3, boundary: 1, diagnostics: 1 }
  );
  assert.equal(byName.agentd.total, 5);
  assert.equal(byName.agentd.done, false);
  assert.equal(byName['pcp-ts'].done, true);
});

test('a package with only diagnostics is listed under its audited name, and tools subfolders roll up', () => {
  const status = guardrailsStatus({
    escapeHatch: escapeHatch(['tools', 'lib', 'as any', 0]),
    boundary: [],
    diagnostics: diagnostics(['tsc', 'tools/fake-pi', 'TS2345', 2], ['eslint', 'tools/fault-proxy', 'x', 1])
  });
  const tools = status.packages.find((p) => p.name === 'tools');
  assert.ok(tools);
  assert.equal(tools.diagnostics, 3);
  assert.equal(status.packages.filter((p) => p.name === 'tools').length, 1);
});

test('a boundary violation outside any audited package is listed under its first two path segments', () => {
  const status = guardrailsStatus({
    escapeHatch: {},
    boundary: [{ file: 'docs/x/y.ts', import: 'z' }],
    diagnostics: {}
  });
  const other = status.packages.find((p) => p.name === 'docs/x');
  assert.ok(other);
  assert.equal(other.boundary, 1);
  assert.equal(other.done, false);
});

test('packages are sorted by name', () => {
  const status = guardrailsStatus({
    escapeHatch: escapeHatch(['e2e', 'lib', 'as any', 0], ['agentd', 'lib', 'as any', 0]),
    boundary: [],
    diagnostics: {}
  });
  assert.deepEqual(
    status.packages.map((p) => p.name),
    ['agentd', 'e2e']
  );
});
