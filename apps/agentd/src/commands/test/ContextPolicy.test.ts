import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { Dispatcher } from '../Dispatcher.js';
import { Session } from '../../sessions/Session.js';

const home = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-policy-dispatch-'));
const previousHome = process.env.PI_FRAME_HOME;
process.env.PI_FRAME_HOME = home;
test.after(() => {
  if (previousHome === undefined) delete process.env.PI_FRAME_HOME; else process.env.PI_FRAME_HOME = previousHome;
  fs.rmSync(home, { recursive: true, force: true });
});

function setup() {
  const session = new Session({ id: `s_${Math.random().toString(16).slice(2)}`, cwd: home });
  session.model = { provider: 'test', id: 'one', contextWindow: 1000000 };
  let runtimeModel = { ...session.model };
  let failPolicy = false;
  const sent: any[] = [];
  const worker = { send: async (command: any) => {
    sent.push(command);
    if (command.command === 'prompt') {
      if (failPolicy) { failPolicy = false; throw new Error('Cannot apply policy'); }
      runtimeModel = { ...runtimeModel, piframeOriginalContextWindow: 1000000,
        piframeContextPolicy: JSON.parse(command.arguments.message.split(' ').slice(1).join(' ')) };
    }
    return { success: true, data: { model: runtimeModel } };
  } };
  const registry: any = {
    getSession: () => session, getIndex: () => ({}), getPiExecutablePath: () => 'pi',
    ensureWorkerForSession: async () => worker, closeWorker: async () => {},
  };
  const dispatcher = new Dispatcher(registry, {} as any, {} as any);
  let sequence = 0;
  const execute = async (type: string, payload: any) => {
    const messages: any[] = [];
    await dispatcher.handle({ state: 'ready', send: (message: any) => messages.push(message) } as any, {
      protocol: 1, kind: 'command', id: `c_${++sequence}`, commandId: `id_${sequence}`, ts: Date.now(),
      type, sessionId: session.id, payload,
    } as any);
    return messages.find(message => message.kind === 'result');
  };
  return { session, sent, execute, fail: () => { failPolicy = true; } };
}

test('Dispatcher context policy: rejects invalid/unbounded max and reserve values', async () => {
  const s = setup();
  try {
    for (const limit of [1000001, 0, -1, 1.5, '200000']) {
      assert.equal((await s.execute('agent.setContextWindowOverride', { limit })).payload.state, 'rejected');
    }
    for (const percent of [0, 100, -1, '5']) {
      assert.equal((await s.execute('agent.setCompactionReservePercent', { percent })).payload.state, 'rejected');
    }
    assert.equal(s.sent.length, 0);
  } finally { await s.session.close(); }
});

test('Dispatcher context policy: acknowledges applied settings and restores them in snapshots/reopen', async () => {
  const s = setup();
  try {
    let response = await s.execute('agent.setContextWindowOverride', { limit: 200000 });
    assert.equal(response.payload.state, 'completed');
    assert.equal(s.session.contextWindowOverride, 200000);
    response = await s.execute('agent.setCompactionReservePercent', { percent: 5 });
    assert.equal(response.payload.data.compactionReservePercent, 5);
    assert.equal(s.session.getSnapshot().runtime.compactionReservePercent, 5);
    assert.equal(s.session.model.contextWindow, 1000000);
    const reopened = new Session({ id: s.session.id, cwd: home });
    assert.equal(reopened.contextWindowOverride, 200000);
    assert.equal(reopened.compactionReservePercent, 5);
    await reopened.close();
    response = await s.execute('agent.setContextWindowOverride', { limit: null });
    assert.equal(response.payload.data.contextWindowOverride, null);
    assert.equal(s.sent.some(c => c.command === 'compact'), false, 'Pi owns compaction; no duplicate daemon compact');
  } finally { await s.session.close(); }
});

test('Dispatcher context policy: failures and active sessions never acknowledge unapplied settings', async () => {
  const s = setup();
  try {
    s.fail();
    assert.equal((await s.execute('agent.setContextWindowOverride', { limit: 200000 })).payload.state, 'failed');
    assert.equal(s.session.contextWindowOverride, null);
    s.session.isStreaming = true;
    assert.equal((await s.execute('agent.setCompactionReservePercent', { percent: 5 })).payload.state, 'rejected');
    s.session.isStreaming = false;
    s.session.readOnly = true;
    assert.equal((await s.execute('agent.setCompactionReservePercent', { percent: 5 })).payload.state, 'rejected');
    assert.equal(s.session.compactionReservePercent, 2.5);
  } finally { await s.session.close(); }
});
