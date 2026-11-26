import test from 'node:test';
import assert from 'node:assert/strict';
import { checkNodeTestTimeouts } from '../src/index.mjs';

const script = (command, path = 'apps/agentd/package.json', name = 'test') => ({ path, name, command });

// Regression for #115: a test that leaked a handle hung `node --test` with no limit.
test('a node --test command without --test-timeout fails, naming the file and script', () => {
  const result = checkNodeTestTimeouts({ commands: [script('node --test dist/**/*.test.js')] });
  assert.equal(result.ok, false);
  assert.equal(result.problems.length, 1);
  assert.equal(result.problems[0].path, 'apps/agentd/package.json');
  assert.equal(result.problems[0].name, 'test');
  assert.match(result.problems[0].message, /--test-timeout/);
});

test('a node --test command with --test-timeout passes', () => {
  const result = checkNodeTestTimeouts({ commands: [script('node --test --test-timeout=120000 dist/**/*.test.js')] });
  assert.deepEqual(result, { ok: true, problems: [] });
});

test('each command of a chain is checked on its own', () => {
  const result = checkNodeTestTimeouts({
    commands: [script('pnpm run build && node --test --test-timeout=1 a.mjs && node --test b.mjs')]
  });
  assert.equal(result.problems.length, 1);
  assert.match(result.problems[0].message, /node --test b\.mjs/);
});

test('commands that do not run node --test are ignored', () => {
  const result = checkNodeTestTimeouts({
    commands: [script('node test/validate-schemas.js'), script('node tools/scripts/test-flutter.js'), script('tsc')]
  });
  assert.deepEqual(result, { ok: true, problems: [] });
});
