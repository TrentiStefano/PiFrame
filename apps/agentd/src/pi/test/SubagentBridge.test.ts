import { test, type TestContext } from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';
import { ensureContextLimitExtension } from '../contextLimitExtension.js';
import { readProperty } from '../../errors/errors.js';

const MANAGER_KEY = Symbol.for('pi-subagents:manager');
const OWNER_KEY = Symbol.for('piframe:subagent-bridge');

type Listener = (data: unknown) => void;

interface UiContext {
  ui: {
    setStatus: (key: string, text: string) => void;
    notify: () => void;
    select: () => void;
    input: () => void;
  };
}

interface AgentRecord {
  id: string;
  status: string;
  type?: string;
  description?: string;
  startedAt?: number;
  toolUses?: number;
}

/** The status JSON the bridge publishes after each change. */
interface BridgeState {
  available: boolean;
  anyRunning: boolean;
  idleSince: number | null;
  agents: Array<{ id: string; status: string; toolUses?: number }>;
}

interface CommandDefinition {
  handler: (args: string, ctx: UiContext) => Promise<void>;
}

interface ToolResult {
  content: Array<{ text: string }>;
  details: { stopped: boolean };
}

interface ToolDefinition {
  name: string;
  execute: (callId: string, params: { agent_id: string }) => Promise<ToolResult>;
}

/** The extension entry point: it receives a Pi object and registers handlers on it. */
type ExtensionEntry = (pi: unknown) => void;

/** A Pi process as far as the bridge can see it, with pi-subagents loaded. */
function fakePi() {
  const listeners = new Map<string, Set<Listener>>();
  const events = {
    on(name: string, fn: Listener) {
      if (!listeners.has(name)) listeners.set(name, new Set());
      listeners.get(name)!.add(fn);
      return () => listeners.get(name)?.delete(fn);
    },
    emit(name: string, data: unknown) {
      for (const fn of [...(listeners.get(name) ?? [])]) fn(data);
    }
  };
  const handlers = new Map<string, Array<(event: unknown, ctx: UiContext) => unknown>>();
  const commands = new Map<string, CommandDefinition>();
  const tools = new Map<string, ToolDefinition>();
  const statuses: string[] = [];
  const ctx: UiContext = {
    ui: {
      setStatus: (key: string, text: string) => {
        if (key === 'piframe-subagents') statuses.push(text);
      },
      notify() {},
      select() {},
      input() {}
    }
  };
  const records = new Map<string, AgentRecord>();
  Reflect.set(globalThis, MANAGER_KEY, {
    hasRunning: () => [...records.values()].some((r) => r.status === 'running' || r.status === 'queued'),
    getRecord: (id: string) => records.get(id)
  });
  // pi-subagents' stop RPC, as in its cross-extension-rpc.ts.
  events.on('subagents:rpc:stop', (data) => {
    const requestId = readProperty(data, 'requestId');
    const agentId = String(readProperty(data, 'agentId'));
    const record = records.get(agentId);
    const reply = !record
      ? { success: false, error: 'Agent not found' }
      : record.status !== 'running'
        ? { success: false, error: 'Agent is not running' }
        : ((record.status = 'stopped'), { success: true });
    events.emit(`subagents:rpc:stop:reply:${String(requestId)}`, reply);
  });
  const pi = {
    events,
    on(name: string, fn: (event: unknown, ctx: UiContext) => unknown) {
      if (!handlers.has(name)) handlers.set(name, []);
      handlers.get(name)!.push(fn);
    },
    registerCommand(name: string, def: CommandDefinition) {
      commands.set(name, def);
    },
    registerTool(def: ToolDefinition) {
      tools.set(def.name, def);
    },
    getSettings: () => ({}),
    setModel: async () => true
  };
  const fire = async (name: string) => {
    for (const fn of handlers.get(name) ?? []) await fn({}, ctx);
  };
  const last = (): BridgeState => {
    const parsed: BridgeState = JSON.parse(statuses[statuses.length - 1]!);
    return parsed;
  };
  return { pi, events, commands, tools, statuses, records, fire, last, ctx };
}

async function loadGeneratedExtension(t: TestContext): Promise<ExtensionEntry> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-bridge-'));
  t.after(() => {
    fs.rmSync(dir, { recursive: true, force: true });
    Reflect.deleteProperty(globalThis, MANAGER_KEY);
    Reflect.deleteProperty(globalThis, OWNER_KEY);
  });
  const file = ensureContextLimitExtension(dir);
  // A fresh URL each time: the module must be the emitted source, not a cache.
  const mod: { default: ExtensionEntry } = await import(`${pathToFileURL(file).href}?t=${Date.now()}-${Math.random()}`);
  return mod.default;
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

  fake.records.set('agent-1', {
    id: 'agent-1',
    status: 'running',
    type: 'worker',
    description: 'Add tests',
    startedAt: 1000,
    toolUses: 13
  });
  fake.events.emit('subagents:started', { id: 'agent-1', type: 'worker', description: 'Add tests' });
  state = fake.last();
  assert.equal(state.anyRunning, true);
  assert.equal(state.idleSince, null);
  assert.deepEqual(
    state.agents.map((a) => [a.id, a.status, a.toolUses]),
    [['agent-1', 'running', 13]]
  );

  // The internal command the daemon sends stops it through the stop RPC.
  await fake.commands.get('piframe-subagent-stop')!.handler('agent-1', fake.ctx);
  state = fake.last();
  assert.equal(state.agents[0]?.status, 'stopped');
  assert.equal(state.anyRunning, false);
  assert.equal(typeof state.idleSince, 'number');

  // A stop that pi-subagents refuses is reported as an error.
  await assert.rejects(fake.commands.get('piframe-subagent-stop')!.handler('agent-1', fake.ctx), /not running/);
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
  assert.match(result.content[0]?.text ?? '', /stopped/);
  assert.equal(result.details.stopped, true);
  assert.equal(fake.records.get('agent-2')?.status, 'stopped');

  const again = await tool.execute('call-2', { agent_id: 'agent-2' });
  assert.equal(again.details.stopped, false);
  assert.match(again.content[0]?.text ?? '', /not running/);
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
  Reflect.deleteProperty(globalThis, MANAGER_KEY);
  extension(fake.pi);
  await fake.fire('session_start');
  assert.equal(fake.last().available, false);
});
