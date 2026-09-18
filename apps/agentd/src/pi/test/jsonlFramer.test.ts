import test from 'node:test';
import * as assert from 'node:assert/strict';
import { JsonlFramer } from '../jsonlFramer.js';

test('JsonlFramer: handles basic single line and CRLF', () => {
  const framer = new JsonlFramer();
  const chunk = Buffer.from('{"hello":"world"}\r\n{"foo":"bar"}\n');
  const results = framer.push(chunk);

  assert.equal(results.length, 2);
  assert.equal(results[0].ok, true);
  assert.deepEqual(results[0].value, { hello: 'world' });
  assert.equal(results[1].ok, true);
  assert.deepEqual(results[1].value, { foo: 'bar' });
});

test('JsonlFramer: does NOT split on U+2028 or U+2029 within string', () => {
  const framer = new JsonlFramer();
  // U+2028 is LINE SEPARATOR (E2 80 A8 in UTF-8)
  // U+2029 is PARAGRAPH SEPARATOR (E2 80 A9 in UTF-8)
  const content = JSON.stringify({ text: "Hello\u2028World\u2029Test" });
  const chunk = Buffer.from(content + '\n');
  const results = framer.push(chunk);

  assert.equal(results.length, 1);
  assert.equal(results[0].ok, true);
  assert.equal(results[0].value.text, "Hello\u2028World\u2029Test");
});

test('JsonlFramer: handles multibyte UTF-8 split across chunks', () => {
  const framer = new JsonlFramer();
  // Emoji '🚀' is 4 bytes: F0 9F 99 80
  const jsonStr = '{"rocket":"🚀"}\n';
  const fullBuf = Buffer.from(jsonStr, 'utf8');

  // Find index of first byte of emoji
  const rocketIdx = fullBuf.indexOf(0xF0);

  // Split chunk right in the middle of the 4-byte emoji sequence (after 2 bytes)
  const part1 = fullBuf.subarray(0, rocketIdx + 2);
  const part2 = fullBuf.subarray(rocketIdx + 2);

  const res1 = framer.push(part1);
  assert.equal(res1.length, 0); // Not complete line yet

  const res2 = framer.push(part2);
  assert.equal(res2.length, 1);
  assert.equal(res2[0].ok, true);
  assert.equal(res2[0].value.rocket, '🚀');
});

test('JsonlFramer: unparseable line returns ok: false without throwing', () => {
  const framer = new JsonlFramer();
  const chunk = Buffer.from('NOT A VALID JSON LINE\n{"ok":true}\n');
  const results = framer.push(chunk);

  assert.equal(results.length, 2);
  assert.equal(results[0].ok, false);
  assert.equal(results[0].raw, 'NOT A VALID JSON LINE');
  assert.equal(results[1].ok, true);
  assert.deepEqual(results[1].value, { ok: true });
});
