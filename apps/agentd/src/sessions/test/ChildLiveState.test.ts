import test from 'node:test';
import * as assert from 'node:assert/strict';
import { childStatus, labelSiblingPrompts, trackChildLiveState, type ChildLiveState } from '../SessionIndex.js';

const user = (text: string) => ({ type: 'message', message: { role: 'user', content: [{ type: 'text', text }] } });
const assistant = (content: unknown[], stopReason: string) =>
  ({ type: 'message', message: { role: 'assistant', content, stopReason } });

test('child live state reports the running tool call and settles on the final answer', () => {
  const live: ChildLiveState = {};
  trackChildLiveState(live, { type: 'session', timestamp: '2026-11-06T14:45:45.222Z' });
  trackChildLiveState(live, user('CONTESTO\nRepository: C:/repo, sito statico promozionale'));
  trackChildLiveState(live, assistant([{ type: 'toolCall', name: 'bash', arguments: { command: 'npm   test' } }], 'toolUse'));
  assert.equal(live.startedAt, Date.parse('2026-11-06T14:45:45.222Z'));
  assert.equal(live.prompt, 'Repository: C:/repo, sito statico promozionale');
  assert.equal(live.activity, 'bash: npm test');
  assert.equal(live.finished, false);
  assert.equal(childStatus({ ...live, updatedAt: 1_000 }, 2_000), 'running');
  assert.equal(childStatus({ ...live, updatedAt: 1_000 }, 1_000 + 11 * 60 * 1000), 'completed');

  trackChildLiveState(live, { type: 'message', message: { role: 'toolResult', content: [] } });
  trackChildLiveState(live, assistant([{ type: 'text', text: 'Fatto.\nTutti i test passano.' }], 'stop'));
  assert.equal(live.activity, 'Tutti i test passano.');
  assert.equal(childStatus(live, Date.now()), 'completed');
});

test('workflow siblings sharing a preamble are labelled by their own task line', () => {
  const preamble = 'CONTESTO\nRepository: C:/repo, sito statico promozionale\nREGOLE TASSATIVE';
  const children = [preamble + '\nOBIETTIVO: scena Three.js isometrica', preamble + '\nCOMPITO: QA finale e correzioni'].map((text) => {
    const live: ChildLiveState = {};
    trackChildLiveState(live, user(text));
    return live;
  });
  labelSiblingPrompts(children);
  assert.deepEqual(children.map((child) => child.prompt), ['OBIETTIVO: scena Three.js isometrica', 'COMPITO: QA finale e correzioni']);
});
