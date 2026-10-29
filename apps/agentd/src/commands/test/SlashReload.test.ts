import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { Dispatcher } from '../Dispatcher.js';

const home = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-slash-reload-'));
const previousHome = process.env.PI_FRAME_HOME;
process.env.PI_FRAME_HOME = home;
test.after(() => {
  if (previousHome === undefined) delete process.env.PI_FRAME_HOME;
  else process.env.PI_FRAME_HOME = previousHome;
  fs.rmSync(home, { recursive: true, force: true });
});

function fixture(options: { streaming?: boolean } = {}) {
  const workerCalls: Array<{ command: string; arguments?: any }> = [];
  const session: any = { id: 's_reload', isStreaming: options.streaming ?? false, isCompacting: false, readOnly: false };
  const worker = {
    send: async (request: { command: string; arguments?: any }) => {
      workerCalls.push(request);
      if (request.command === 'get_commands') {
        return { success: true, data: { commands: [{ name: 'caveman', description: 'Caveman', source: 'extension' }] } };
      }
      if (request.command === 'get_state') {
        return { success: true, data: { model: { piframeContextPolicy: { limit: null, percent: 2.5 } } } };
      }
      return { success: true, data: {} };
    },
  };
  const registry: any = {
    getSession: (id: string) => (id === session.id ? session : undefined),
    ensureWorkerForSession: async () => worker,
    getIndex: () => ({}),
    getPiExecutablePath: () => 'node',
  };
  const dispatcher = new Dispatcher(registry, { broadcast() {}, broadcastLocal() {} } as any, {
    list: async () => [], update: async () => ({}), remove: async () => ({}), pin: async () => ({}),
  } as any);
  const sent: any[] = [];
  const conn = { id: 'c1', send: (message: any) => sent.push(typeof message === 'string' ? JSON.parse(message) : message) } as any;
  let counter = 0;
  const run = async (type: string, payload: Record<string, unknown>) => {
    counter += 1;
    const start = sent.length;
    await dispatcher.handle(conn, {
      protocol: 1, kind: 'command', id: `m${counter}`, ts: Date.now(), commandId: `cmd_${counter}`,
      type, sessionId: session.id, payload,
    } as any);
    return sent.slice(start).find((message) => message.kind === 'result');
  };
  return { workerCalls, session, run };
}

test('/reload runs the internal reload command and reapplies the policy, never sending text to the model', async () => {
  const { workerCalls, run } = fixture();
  const result = await run('agent.prompt', { text: '/reload' });
  assert.equal(result.payload.state, 'completed');
  const prompts = workerCalls.filter((call) => call.command === 'prompt').map((call) => call.arguments.message);
  assert.equal(prompts[0], '/piframe-reload');
  assert.ok(prompts.every((message) => message !== '/reload'));
  assert.ok(prompts.some((message) => message.startsWith('/piframe-context-policy ')));
});

test('/reload is refused while the agent is streaming instead of queuing text', async () => {
  const { workerCalls, run } = fixture({ streaming: true });
  const result = await run('agent.prompt', { text: '/reload', streamingBehavior: 'steer' });
  assert.notEqual(result.payload.state, 'completed');
  assert.equal(workerCalls.length, 0);
});

test('ordinary prompts still go to the model unchanged', async () => {
  const { workerCalls, run } = fixture();
  await run('agent.prompt', { text: 'please reload the config file' });
  assert.deepEqual(workerCalls.filter((call) => call.command === 'prompt').map((call) => call.arguments.message), ['please reload the config file']);
});

test('agent.getCommands returns every Pi built-in before extension commands', async () => {
  const { run } = fixture();
  const result = await run('agent.getCommands', {});
  assert.equal(result.payload.state, 'completed');
  const commands = result.payload.data.commands;
  const builtinNames = commands.filter((command: { source: string }) => command.source === 'builtin').map((command: { name: string }) => command.name);
  assert.deepEqual(builtinNames, [
    'settings', 'model', 'tree', 'thinking', 'scoped-models', 'export', 'import', 'share', 'bug', 'copy',
    'name', 'session', 'changelog', 'hotkeys', 'fork', 'clone', 'trust', 'login', 'logout', 'new', 'compact',
    'resume', 'reload', 'quit',
  ]);
  assert.equal(commands.at(-1).name, 'caveman');
  assert.equal(commands.find((command: { name: string }) => command.name === 'model').argumentHint, '<provider/model>');
});

test('native built-in commands are never forwarded as model prompts', async () => {
  const { workerCalls, run } = fixture();
  const result = await run('agent.prompt', { text: '/settings' });
  assert.equal(result.payload.state, 'rejected');
  assert.match(result.payload.error, /Pi built-in command/);
  assert.equal(workerCalls.some((call) => call.command === 'prompt'), false);
});
