import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { awaitSubagentStopped, mapLiveStatus, parseLiveSubagents, resolveSubagentStatus, type SubagentRuntime } from '../liveSubagents.js';
import { Session } from '../Session.js';

const report = (agents: any[], anyRunning: boolean) =>
  JSON.stringify({ v: 1, available: true, anyRunning, idleSince: anyRunning ? null : 5, bridgeStartedAt: 1, agents });

const runtime = (live: any, extra: Partial<SubagentRuntime> = {}): SubagentRuntime => ({
  live: live ? parseLiveSubagents(live, 10) : null,
  workerAlive: true,
  workerGone: false,
  ...extra,
});

test('parseLiveSubagents accepts only the bridge format', () => {
  assert.equal(parseLiveSubagents('not json'), null);
  assert.equal(parseLiveSubagents(JSON.stringify({ v: 2, agents: [] })), null);
  const state = parseLiveSubagents(report([{ id: 'a', status: 'running' }, { status: 'x' }], true), 42)!;
  assert.equal(state.anyRunning, true);
  assert.equal(state.receivedAt, 42);
  assert.deepEqual(state.agents.map((a) => a.id), ['a']);
});

test('mapLiveStatus speaks PiFrame', () => {
  assert.equal(mapLiveStatus('queued'), 'running');
  assert.equal(mapLiveStatus('aborted'), 'stopped');
  assert.equal(mapLiveStatus('steered'), 'steered');
  assert.equal(mapLiveStatus('error'), 'error');
});

test('the live registry wins over session-file guesses', () => {
  // Hung in a long tool call: the file went quiet, /agents says running.
  const hung = runtime(report([{ id: 'a', status: 'running' }], true));
  assert.equal(resolveSubagentStatus({ id: 'a', status: 'completed' }, hung), 'running');
  // Stopped from /agents or PiFrame.
  const stopped = runtime(report([{ id: 'a', status: 'stopped' }], false));
  assert.equal(resolveSubagentStatus({ id: 'a', status: 'running' }, stopped), 'stopped');
});

test('agents the worker does not know are not running', () => {
  const idle = runtime(report([], false));
  assert.equal(resolveSubagentStatus({ id: 'old', status: 'running' }, idle), 'stopped');
  assert.equal(resolveSubagentStatus({ id: 'old', status: 'running', finished: true }, idle), 'completed');
  // Something else runs: a top-level agent from an earlier process is still gone…
  const busy = runtime(report([{ id: 'other', status: 'running' }], true));
  assert.equal(resolveSubagentStatus({ id: 'old', status: 'running' }, busy), 'stopped');
  // …but a workflow's own agent is never listed, so the files decide.
  assert.equal(resolveSubagentStatus({ id: 'wf-child', status: 'running', unlinked: true }, busy), 'running');
});

test('once the worker is gone nothing it ran is running', () => {
  const gone = runtime(null, { workerAlive: false, workerGone: true });
  assert.equal(resolveSubagentStatus({ id: 'a', status: 'running' }, gone), 'stopped');
  assert.equal(resolveSubagentStatus({ id: 'a', status: 'completed' }, gone), 'completed');
  // A session PiFrame never ran (maybe open in a Pi terminal) keeps the guess.
  const unknown = runtime(null, { workerAlive: false, workerGone: false });
  assert.equal(resolveSubagentStatus({ id: 'a', status: 'running' }, unknown), 'running');
});

test('Session keeps the bridge report as live state, never as a status line', () => {
  const session = new Session({ id: 's_live', cwd: process.cwd() } as any);
  const emitted = session.dispatchPiEvent({
    type: 'extension_ui_request',
    method: 'setStatus',
    statusKey: 'piframe-subagents',
    statusText: report([{ id: 'a', status: 'running' }], true),
  });
  assert.deepEqual(emitted, []);
  assert.equal(session.hasRunningSubagents, true);
  assert.equal(session.liveSubagents?.agents[0].id, 'a');

  session.markWorkerGone(123);
  assert.equal(session.liveSubagents, null);
  assert.equal(session.hasRunningSubagents, false);
  assert.equal(session.workerGoneAt, 123);
  session.markWorkerStarted();
  assert.equal(session.workerGoneAt, null);
});

test('awaitSubagentStopped waits for the bridge to confirm the stop', async () => {
  let live = parseLiveSubagents(report([{ id: 'a', status: 'running' }], true));
  setTimeout(() => { live = parseLiveSubagents(report([{ id: 'a', status: 'stopped' }], false)); }, 30);
  assert.equal(await awaitSubagentStopped(() => live, 'a', 1000, 10), true);
  // Never confirmed: false after the timeout.
  const stuck = parseLiveSubagents(report([{ id: 'b', status: 'running' }], true));
  assert.equal(await awaitSubagentStopped(() => stuck, 'b', 60, 10), false);
  // Gone from the registry with nothing running counts as stopped.
  const empty = parseLiveSubagents(report([], false));
  assert.equal(await awaitSubagentStopped(() => empty, 'c', 60, 10), true);
});
