import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { Session } from '../Session.js';

test('a tool event without a call id is keyed by undefined, not by the string "undefined"', () => {
  const session = new Session({ id: 's_tool_missing_id', cwd: process.cwd() });
  session.dispatchPiEvent({ type: 'tool_execution_start', toolName: 'bash' });

  assert.equal(session.activeTools.has(undefined), true);
  assert.equal(session.activeTools.has('undefined'), false);

  session.dispatchPiEvent({ type: 'tool_execution_end', toolName: 'bash', result: 'ok' });
  assert.equal(session.activeTools.get(undefined)?.isRunning, false);
  assert.equal(session.activeTools.has('undefined'), false);
});

test('tool events with a call id are keyed by that id', () => {
  const session = new Session({ id: 's_tool_id', cwd: process.cwd() });
  session.dispatchPiEvent({ type: 'tool_execution_start', toolCallId: 'call_1', toolName: 'bash' });
  assert.equal(session.activeTools.get('call_1')?.isRunning, true);
});

test('text deltas without a content index accumulate into the first block', () => {
  const session = new Session({ id: 's_text_index', cwd: process.cwd() });
  session.dispatchPiEvent({ type: 'message_update', assistantMessageEvent: { type: 'text_delta', delta: 'Hel' } });
  session.dispatchPiEvent({ type: 'message_update', assistantMessageEvent: { type: 'text_delta', delta: 'lo' } });
  assert.equal(session.liveMessage?.content.length, 1);
  assert.equal(session.liveMessage?.content[0]?.text, 'Hello');
});
