import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  assertSafeHome,
  encodeParams,
  isMissingProcessError,
  listScenarios,
  parseArgs,
  parseSelector,
  seedHarnessHome,
  validateScenarioName,
  writeFakePiShims,
} from './pf-harness.mjs';

test('parseSelector handles keys, text, defaults, and matching index', () => {
  assert.deepEqual(parseSelector('key:composer-send'), { type: 'key', value: 'composer-send' });
  assert.deepEqual(parseSelector('text:New session#2'), { type: 'text', value: 'New session', index: 2 });
  assert.deepEqual(parseSelector('New session'), { type: 'text', value: 'New session' });
  assert.throws(() => parseSelector(''), /cannot be empty/i);
});

test('assertSafeHome refuses the normal PiFrame homes', () => {
  const userHome = path.resolve('/user/home');
  assert.throws(() => assertSafeHome(path.join(userHome, '.piframe'), userHome), /unsafe harness home/i);
  assert.throws(() => assertSafeHome(path.join(userHome, '.piframe-dev'), userHome), /unsafe harness home/i);
  assert.throws(() => assertSafeHome(path.join(userHome, '.piframe', 'nested'), userHome), /unsafe harness home/i);
  assert.equal(assertSafeHome(path.join(userHome, '.piframe-harness', 'test'), userHome), path.join(userHome, '.piframe-harness', 'test'));
});

test('isMissingProcessError recognizes taskkill exit code and localized output fallback', () => {
  assert.equal(isMissingProcessError({ code: 128, stderr: 'localized message' }), true);
  assert.equal(isMissingProcessError({ message: 'ERRORE: processo "29328" non trovato.' }), true);
  assert.equal(isMissingProcessError({ stderr: 'Access is denied.' }), false);
});

test('argument parsing supports harness pointer, tree, media, and seed options', () => {
  assert.deepEqual(parseArgs(['drag', 'key:divider', '12', '-4', '--run', 'inspect']), {
    positional: ['drag', 'key:divider', '12', '-4'],
    options: { run: 'inspect' },
  });
  assert.deepEqual(parseArgs(['tree', '--limit', '80', '--depth=12', '--filter', 'notes.md']), {
    positional: ['tree'],
    options: { limit: '80', depth: '12', filter: 'notes.md' },
  });
  assert.deepEqual(parseArgs(['media', '--text-scale', '1.4', '--reduce-motion', 'on', '--brightness', 'dark', '--reset']), {
    positional: ['media'],
    options: { 'text-scale': '1.4', 'reduce-motion': 'on', brightness: 'dark', reset: true },
  });
  assert.deepEqual(parseArgs(['start', '--seed']), {
    positional: ['start'],
    options: { seed: true },
  });
});

test('scenario names are validated against the fake-pi scenario catalog', () => {
  assert.ok(listScenarios().some((scenario) => scenario.name === 'hello-world'));
  assert.equal(validateScenarioName('hello-world'), 'hello-world');
  assert.throws(() => validateScenarioName('../package.json'), /unknown fake-pi scenario/i);
});

test('seed rejects protected PiFrame homes before creating fixtures', async () => {
  const userHome = path.resolve('/user/home');
  await assert.rejects(
    seedHarnessHome(path.join(userHome, '.piframe', 'seed'), userHome),
    /unsafe harness home/i,
  );
  await assert.rejects(
    seedHarnessHome(path.join(userHome, '.piframe-dev'), userHome),
    /unsafe harness home/i,
  );
});

test('encodeParams preserves strings and JSON-encodes other values', () => {
  assert.deepEqual(encodeParams({ text: 'hello', index: 2, selector: { type: 'key' }, enabled: false }), {
    text: 'hello', index: '2', selector: '{"type":"key"}', enabled: 'false',
  });
});

test('writeFakePiShims creates a fresh run home before writing the shims', () => {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'pf-harness-shim-'));
  try {
    const home = path.join(base, 'brand-new-run');
    writeFakePiShims(home);
    const shim = process.platform === 'win32' ? 'pi.cmd' : 'pi';
    assert.ok(fs.existsSync(path.join(home, shim)));
    assert.ok(fs.existsSync(path.join(home, 'node_modules', 'npm', 'bin', 'npm-cli.js')));
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});
