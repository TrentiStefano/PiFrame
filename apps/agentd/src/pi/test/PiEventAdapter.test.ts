import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { adaptPiEvent } from '../PiEventAdapter.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

test('PiEventAdapter: maps agent_start and text_delta', () => {
  const ctx = { sessionId: 'test_session' };

  const startEvt = { type: 'agent_start' };
  const startPcp = adaptPiEvent(startEvt, ctx);
  assert.equal(startPcp.length, 1);
  assert.equal(startPcp[0].type, 'run.started');

  const updateEvt = {
    type: 'message_update',
    assistantMessageEvent: {
      type: 'text_delta',
      contentIndex: 0,
      delta: 'Hello world'
    }
  };
  const updatePcp = adaptPiEvent(updateEvt, ctx);
  assert.equal(updatePcp.length, 1);
  assert.equal(updatePcp[0].type, 'text.delta');
  assert.equal(updatePcp[0].payload.delta, 'Hello world');
  assert.equal(updatePcp[0].payload.contentIndex, 0);
});

test('PiEventAdapter: maps agent_end without retry to run.ended and run.settled', () => {
  const ctx = { sessionId: 'test_session' };
  const endEvt = { type: 'agent_end', willRetry: false };
  const endPcp = adaptPiEvent(endEvt, ctx);
  assert.equal(endPcp.length, 2);
  assert.equal(endPcp[0].type, 'run.ended');
  assert.equal(endPcp[1].type, 'run.settled');
});

test('PiEventAdapter: processes real fixture file text-only.jsonl', () => {
  const fixturePath = path.resolve(__dirname, '../../../../../packages/pcp-spec/fixtures/pi/text-only.jsonl');
  if (!fs.existsSync(fixturePath)) {
    return; // Skip if path different
  }

  const lines = fs.readFileSync(fixturePath, 'utf8').split('\n').filter(l => l.trim().length > 0);
  const ctx = { sessionId: 'session_fixture' };
  const allEvents: any[] = [];

  for (const line of lines) {
    const raw = JSON.parse(line);
    const pcpList = adaptPiEvent(raw, ctx);
    allEvents.push(...pcpList);
  }

  assert.ok(allEvents.length > 0);
  assert.ok(allEvents.some(e => e.type === 'run.started'));
  assert.ok(allEvents.some(e => e.type === 'text.delta'));
  assert.ok(allEvents.some(e => e.type === 'run.settled'));
});
