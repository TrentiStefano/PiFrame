import test from 'node:test';
import * as assert from 'node:assert/strict';
import { Dispatcher } from '../Dispatcher.js';
import type { Session } from '../../sessions/Session.js';
import type { SessionRegistry } from '../../sessions/SessionRegistry.js';
import type { PcpCommandType } from '@piframe/pcp-ts';
import {
  at,
  commandEnvelope,
  fakeConnection,
  fakeConnectionManager,
  fakeIndex,
  fakePiPackages,
  fakeRegistry,
  fakeRemoteManager,
  parseSent,
  type SentMessage
} from './fakes.js';

function fixture() {
  let calls = 0;
  let release: () => void = () => {};
  const registry = fakeRegistry({
    getSession: () => ({ id: 's1', readOnly: false }) as Session,
    getSubagents: async () => {
      calls += 1;
      await new Promise<void>((resolve) => {
        release = resolve;
      });
      return [{ id: `agent-${calls}` }] as Awaited<ReturnType<SessionRegistry['getSubagents']>>;
    },
    subagentRuntime: () => ({ live: null, workerAlive: false, workerGone: false }),
    getIndex: () => fakeIndex(),
    getPiExecutablePath: () => 'node'
  });
  const dispatcher = new Dispatcher(
    registry,
    fakeConnectionManager({ broadcast() {}, broadcastLocal() {} }),
    fakePiPackages({
      list: async () => [],
      update: async () => ({}),
      remove: async () => ({}),
      pin: async () => ({})
    }),
    fakeRemoteManager({
      on() {},
      getAuthManager: () => ({ getDevice: () => ({ mode: 'control' }) })
    })
  );
  const sent: SentMessage[] = [];
  const conn = fakeConnection({
    id: 'c1',
    deviceId: 'd1',
    isRemote: false,
    send: (m) => sent.push(parseSent(m)) > 0
  });
  let counter = 0;
  const run = (type: PcpCommandType) => {
    counter += 1;
    return dispatcher.handle(
      conn,
      commandEnvelope(type, {}, { id: `m${counter}`, commandId: `cmd_${counter}`, sessionId: 's1' })
    );
  };
  return { run, sent, calls: () => calls, release: () => release() };
}

test('identical reads in flight on one connection share one execution and both get a result', async () => {
  const f = fixture();
  const first = f.run('session.subagents');
  const second = f.run('session.subagents');
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(f.calls(), 1);
  f.release();
  await Promise.all([first, second]);
  const results = f.sent.filter((m) => m.kind === 'result');
  assert.deepEqual(
    results.map((m) => [m.commandId, at(m, 'payload', 'state')]),
    [
      ['cmd_1', 'completed'],
      ['cmd_2', 'completed']
    ]
  );
  assert.deepEqual(at(results[1], 'payload', 'data'), at(results[0], 'payload', 'data'));

  // Once finished, the next request runs again instead of reusing a stale result.
  const third = f.run('session.subagents');
  await new Promise((resolve) => setImmediate(resolve));
  f.release();
  await third;
  assert.equal(f.calls(), 2);
});
