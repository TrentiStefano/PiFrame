import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { parseTscOutput, parseEslintJson, checkDiagnostics } from '../src/index.mjs';

const fixture = (name) => readFileSync(fileURLToPath(new URL(`./fixtures/${name}`, import.meta.url)), 'utf8');
const REPO = 'C:\\Repo';

test('parses tsc output into per-rule diagnostics (continuation lines ignored)', () => {
  const out = parseTscOutput(fixture('tsc-output.txt'), { package: 'apps/agentd' });
  assert.deepEqual(
    out.map((d) => [d.tool, d.package, d.rule, d.file, d.line, d.severity]),
    [
      ['tsc', 'apps/agentd', 'TS2532', 'src/workspace/gitClient.ts', 12, 'ERROR'],
      ['tsc', 'apps/agentd', 'TS2375', 'src/sessions/SessionIndex.ts', 40, 'ERROR'],
      ['tsc', 'apps/agentd', 'TS6133', 'src/sessions/SessionIndex.ts', 41, 'ERROR'],
      ['tsc', 'apps/agentd', 'TS2532', 'test/x.test.ts', 7, 'ERROR']
    ]
  );
  assert.equal(
    out[1].message,
    "Type 'undefined' is not assignable to type 'string' with 'exactOptionalPropertyTypes: true'."
  );
});

test('parser returns nothing for a clean tsc run', () => {
  assert.deepEqual(parseTscOutput('', { package: 'p' }), []);
});

test('parses ESLint JSON per package and rule, attributing files to the package that holds them', () => {
  const out = parseEslintJson(fixture('eslint-output.json'), {
    repoRoot: REPO,
    packages: ['apps/agentd', 'packages/pcp-ts', 'test/e2e']
  });
  assert.deepEqual(
    out.map((d) => [d.tool, d.package, d.rule, d.file, d.line, d.severity]),
    [
      ['eslint', 'apps/agentd', '@typescript-eslint/no-floating-promises', 'apps/agentd/src/pi/worker.ts', 10, 'ERROR'],
      ['eslint', 'apps/agentd', '@typescript-eslint/require-await', 'apps/agentd/src/pi/worker.ts', 20, 'WARNING'],
      ['eslint', 'test/e2e', 'parse-error', 'test/e2e/src/spec.ts', 1, 'ERROR']
    ]
  );
});

test('ESLint and tsc counts feed the ratchet under separate tools', () => {
  const diagnostics = [
    ...parseTscOutput(fixture('tsc-output.txt'), { package: 'apps/agentd' }),
    ...parseEslintJson(fixture('eslint-output.json'), { repoRoot: REPO, packages: ['apps/agentd', 'test/e2e'] })
  ];
  const baseline = {
    tsc: { 'apps/agentd': { TS2532: 2, TS2375: 1, TS6133: 1 } },
    eslint: {
      'apps/agentd': { '@typescript-eslint/no-floating-promises': 1, '@typescript-eslint/require-await': 1 },
      'test/e2e': { 'parse-error': 1 }
    }
  };
  assert.deepEqual(checkDiagnostics({ diagnostics, baseline }), { ok: true, problems: [] });
  const raised = checkDiagnostics({
    diagnostics,
    baseline: { ...baseline, eslint: { ...baseline.eslint, 'test/e2e': {} } }
  });
  assert.equal(raised.ok, false);
  assert.equal(raised.problems[0].tool, 'eslint');
});
