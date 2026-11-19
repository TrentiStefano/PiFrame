import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';
import { ensureContextLimitExtension } from '../contextLimitExtension.js';

const MANAGER_KEY = Symbol.for('pi-subagents:manager');
const OWNER_KEY = Symbol.for('piframe:subagent-bridge');

/** A Pi process as far as the bridge can see it, with pi-subagents loaded. */
function fakePi() {
  const listeners = new Map<string, Set<(data: any) => void>>();
  const events = {
    on(name: string, fn: (data: any) => void) {
      if (!listeners.has(name)) listeners.set(name, new Set());
      listeners.get(name)!.add(fn);
      return () => listeners.get(name)?.delete(fn);
    },
    emit(name: string, data: any) {
      for (const fn of [...(listeners.get(name) ?? [])]) fn(data);
    },
  };
  const handlers = new Map<string, Array<(event: any, ctx: any) => any>>();
  const commands = new Map<string, any>();
  const tools = new Map<string, any>();
  const statuses: string[] = [];
  const ctx = { ui: { setStatus: (key: string, text: string) => { if (key === 'piframe-subagents') statuses.push(text); }, notify() {}, select() {}, input() {} } };
  const records = new Map<string, any>();
  (globalThis as any)[MANAGER_KEY] = {
    hasRunning: () => [...records.values()].some((r) => r.status === 'running' || r.status === 'queued'),
    getRecord: (id: string) => records.get(id),
  };
  // pi-subagents' stop RPC, as in its cross-extension-rpc.ts.
  events.on('subagents:rpc:stop', ({ requestId, agentId }: any) => {
    const record = records.get(agentId);
    const reply = !record ? { success: false, error: 'Agent not found' }
      : record.status !== 'running' ? { success: false, error: 'Agent is not running' }
      : (record.status = 'stopped', { success: true });
    events.emit(`subagents:rpc:stop:reply:${requestId}`, reply);
  });
  const pi = {
    events,
    on(name: string, fn: any) { if (!handlers.has(name)) handlers.set(name, []); handlers.get(name)!.push(fn); },
    registerCommand(name: string, def: any) { commands.set(name, def); },
    registerTool(def: any) { tools.set(def.name, def); },
    getSettings: () => ({}),
    setModel: async () => true,
  };
  const fire = async (name: string) => { for (const fn of handlers.get(name) ?? []) await fn({}, ctx); };
  const last = () => JSON.parse(statuses[statuses.length - 1]);
  return { pi, events, commands, tools, statuses, records, fire, last, ctx };
}

async function loadGeneratedExtension(t: any) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-bridge-'));
  t.after(() => {
    fs.rmSync(dir, { recursive: true, force: true });
    delete (globalThis as any)[MANAGER_KEY];
    delete (globalThis as any)[OWNER_KEY];
  });
  const file = ensureContextLimitExtension(dir);
  // A fresh URL each time: the module must be the emitted source, not a cache.
  const mod = await import(`${pathToFileURL(file).href}?t=${Date.now()}-${Math.random()}`);
  return mod.default as (pi: any) => void;
}

test('the generated extension reports pi-subagents state and stops agents for real', async (t) => {
  const extension = await loadGeneratedExtension(t);
  const fake = fakePi();
  extension(fake.pi);
  await fake.fire('session_start');

  let state = fake.last();
  assert.equal(state.available, true);
  assert.equal(state.anyRunning, false);
  assert.deepEqual(state.agents, []);

  fake.records.set('agent-1', { id: 'agent-1', status: 'running', type: 'worker', description: 'Add tests', startedAt: 1000, toolUses: 13 });
  fake.events.emit('subagents:started', { id: 'agent-1', type: 'worker', description: 'Add tests' });
  state = fake.last();
  assert.equal(state.anyRunning, true);
  assert.equal(state.idleSince, null);
  assert.deepEqual(state.agents.map((a: any) => [a.id, a.status, a.toolUses]), [['agent-1', 'running', 13]]);

  // The internal command the daemon sends stops it through the stop RPC.
  await fake.commands.get('piframe-subagent-stop').handler('agent-1', fake.ctx);
  state = fake.last();
  assert.equal(state.agents[0].status, 'stopped');
  assert.equal(state.anyRunning, false);
  assert.equal(typeof state.idleSince, 'number');

  // A stop that pi-subagents refuses is reported as an error.
  await assert.rejects(fake.commands.get('piframe-subagent-stop').handler('agent-1', fake.ctx), /not running/);
});

test('the main agent gets a stop_subagent tool that really stops the agent', async (t) => {
  const extension = await loadGeneratedExtension(t);
  const fake = fakePi();
  extension(fake.pi);
  await fake.fire('session_start');
  fake.records.set('agent-2', { id: 'agent-2', status: 'running' });
  fake.events.emit('subagents:started', { id: 'agent-2' });

  const tool = fake.tools.get('stop_subagent');
  assert.ok(tool, 'stop_subagent is registered');
  const result = await tool.execute('call-1', { agent_id: 'agent-2' });
  assert.match(result.content[0].text, /stopped/);
  assert.equal(result.details.stopped, true);
  assert.equal(fake.records.get('agent-2').status, 'stopped');

  const again = await tool.execute('call-2', { agent_id: 'agent-2' });
  assert.equal(again.details.stopped, false);
  assert.match(again.content[0].text, /not running/);
});

test('subagent sessions re-activating the extension stay silent', async (t) => {
  const extension = await loadGeneratedExtension(t);
  const root = fakePi();
  extension(root.pi);
  const child = fakePi();
  extension(child.pi);
  assert.equal(child.commands.has('piframe-subagent-stop'), false);
  assert.equal(child.tools.has('stop_subagent'), false);
  assert.equal(root.commands.has('piframe-subagent-stop'), true);
  // The context-limit part still loads in both.
  assert.equal(child.commands.has('piframe-reload'), true);
});

test('without pi-subagents the bridge reports it unavailable', async (t) => {
  const extension = await loadGeneratedExtension(t);
  const fake = fakePi();
  delete (globalThis as any)[MANAGER_KEY];
  extension(fake.pi);
  await fake.fire('session_start');
  assert.equal(fake.last().available, false);
});
