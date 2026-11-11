import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { assertSafeHome, encodeParams, isMissingProcessError, parseSelector } from './pf-harness.mjs';

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

test('encodeParams preserves strings and JSON-encodes other values', () => {
  assert.deepEqual(encodeParams({ text: 'hello', index: 2, selector: { type: 'key' }, enabled: false }), {
    text: 'hello', index: '2', selector: '{"type":"key"}', enabled: 'false',
  });
});
