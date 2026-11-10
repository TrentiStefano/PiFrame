import test from 'node:test';
import * as assert from 'node:assert/strict';
import { Dispatcher } from '../Dispatcher.js';

function fixture() {
  let calls = 0;
  let release: () => void = () => {};
  const registry: any = {
    getSession: () => ({ id: 's1', readOnly: false }),
    getSubagents: async () => {
      calls += 1;
      await new Promise<void>((resolve) => { release = resolve; });
      return [{ id: `agent-${calls}` }];
    },
    getIndex: () => ({}),
    getPiExecutablePath: () => 'node',
  };
  const dispatcher = new Dispatcher(registry, { broadcast() {}, broadcastLocal() {} } as any, {
    list: async () => [], update: async () => ({}), remove: async () => ({}), pin: async () => ({}),
  } as any, {
    on() {},
    getAuthManager: () => ({ getDevice: () => ({ mode: 'control' }) }),
  } as any);
  const sent: any[] = [];
  const conn = { id: 'c1', deviceId: 'd1', isRemote: false, send: (m: any) => sent.push(typeof m === 'string' ? JSON.parse(m) : m) } as any;
  let counter = 0;
  const run = (type: string) => {
    counter += 1;
    return dispatcher.handle(conn, {
      protocol: 1, kind: 'command', id: `m${counter}`, ts: Date.now(), commandId: `cmd_${counter}`,
      type, sessionId: 's1', payload: {},
    } as any);
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
  assert.deepEqual(results.map((m) => [m.commandId, m.payload.state]), [['cmd_1', 'completed'], ['cmd_2', 'completed']]);
  assert.deepEqual(results[1].payload.data, results[0].payload.data);

  // Once finished, the next request runs again instead of reusing a stale result.
  const third = f.run('session.subagents');
  await new Promise((resolve) => setImmediate(resolve));
  f.release();
  await third;
  assert.equal(f.calls(), 2);
});
