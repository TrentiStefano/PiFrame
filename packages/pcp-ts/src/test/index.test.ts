import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  parseIncoming,
  isEnvelope,
  makeEnvelope,
  encode,
  type PcpMessage
} from '../index.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const pcpFixturesDir = path.resolve(__dirname, '../../../../packages/pcp-spec/fixtures/pcp');

describe('@pi-crust/pcp-ts', () => {
  it('validates envelope structure correctly', () => {
    assert.strictEqual(isEnvelope(null), false);
    assert.strictEqual(isEnvelope({}), false);
    assert.strictEqual(isEnvelope({ protocol: 2, kind: 'hello' }), false);

    const validEnv = makeEnvelope('event', 'text.delta', { delta: 'hi' }, { sessionId: 's1', seq: 1 });
    assert.strictEqual(isEnvelope(validEnv), true);
  });

  it('preserves forward compatibility on extra fields', () => {
    const json = JSON.stringify({
      protocol: 1,
      kind: 'command',
      id: 'cmd_test',
      ts: 1234567,
      commandId: 'c1',
      type: 'agent.prompt',
      payload: { message: 'hello' },
      futureField: 'compatible',
      anotherMetadata: 123
    });

    const res = parseIncoming(json);
    assert.strictEqual(res.ok, true);
    if (res.ok) {
      assert.strictEqual((res.value as any).futureField, 'compatible');
    }
  });

  it('rejects malformed JSON frames', () => {
    const res = parseIncoming('{ not valid json');
    assert.strictEqual(res.ok, false);
    if (!res.ok) {
      assert.strictEqual(res.error.payload.code, 'INVALID_MESSAGE');
      assert.ok(res.error.payload.message.includes('Malformed JSON frame'));
    }
  });

  it('validates all valid PCP client fixtures', () => {
    const validFiles = ['hello.valid.json', 'command.valid.json', 'pong.valid.json'];
    for (const f of validFiles) {
      const content = fs.readFileSync(path.join(pcpFixturesDir, f), 'utf8');
      const res = parseIncoming(content);
      assert.strictEqual(res.ok, true, `Expected ${f} to parse successfully`);
    }
  });

  it('rejects all invalid PCP client fixtures', () => {
    const invalidFiles = ['hello.invalid.json', 'command.invalid.json'];
    for (const f of invalidFiles) {
      const content = fs.readFileSync(path.join(pcpFixturesDir, f), 'utf8');
      const res = parseIncoming(content);
      assert.strictEqual(res.ok, false, `Expected ${f} to fail validation`);
      if (!res.ok) {
        assert.strictEqual(res.error.payload.code, 'INVALID_MESSAGE');
      }
    }
  });

  it('performs encoding round-trip successfully', () => {
    const env = makeEnvelope('ack', 'command.ack', { state: 'accepted' }, { commandId: 'cmd_01' });
    const encoded = encode(env as PcpMessage);
    const parsed = JSON.parse(encoded);
    assert.strictEqual(parsed.kind, 'ack');
    assert.strictEqual(parsed.commandId, 'cmd_01');
    assert.strictEqual(parsed.payload.state, 'accepted');
  });
});
