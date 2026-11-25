import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { Dispatcher } from '../Dispatcher.js';
import { readProperty } from '../../errors/errors.js';
import type { Session } from '../../sessions/Session.js';
import type { PiCommand } from '../../pi/piCommands.js';
import type { PcpCommandType } from '@piframe/pcp-ts';
import {
  commandEnvelope,
  fakeConnection,
  fakeConnectionManager,
  fakePiPackages,
  at,
  fakeIndex,
  fakeRegistry,
  fakeRemoteManager,
  fakeUiBroker,
  fakeWorker,
  parseSent,
  type SentMessage
} from './fakes.js';

const home = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-slash-reload-'));
const previousHome = process.env.PI_FRAME_HOME;
process.env.PI_FRAME_HOME = home;
test.after(() => {
  if (previousHome === undefined) delete process.env.PI_FRAME_HOME;
  else process.env.PI_FRAME_HOME = previousHome;
  fs.rmSync(home, { recursive: true, force: true });
});

interface CommandEntry {
  name: string;
  source?: string;
  argumentHint?: string;
}

function isCommandEntry(value: unknown): value is CommandEntry {
  return typeof readProperty(value, 'name') === 'string';
}

/** The command list a getCommands result carries; a missing list reads as empty. */
function commandsOf(result: SentMessage | undefined): CommandEntry[] {
  const list: unknown = at(result, 'payload', 'data', 'commands');
  return Array.isArray(list) ? list.filter(isCommandEntry) : [];
}

function fixture(options: { streaming?: boolean; piStillBusy?: boolean; state?: Record<string, unknown> } = {}) {
  const workerCalls: PiCommand[] = [];
  const session = {
    id: 's_reload',
    isStreaming: options.streaming ?? false,
    isCompacting: false,
    readOnly: false
  } as Session;
  const worker = fakeWorker({
    send: async (request: PiCommand) => {
      workerCalls.push(request);
      if (options.piStillBusy && request.command === 'prompt') {
        throw new Error(
          "Agent is already processing. Specify streamingBehavior ('steer' or 'followUp') to queue the message."
        );
      }
      if (request.command === 'get_commands') {
        return {
          type: 'response',
          success: true,
          data: {
            commands: [
              { name: 'caveman', description: 'Caveman', source: 'extension' },
              { name: 'piframe-auth-login', description: 'Internal login', source: 'extension' }
            ]
          }
        };
      }
      if (request.command === 'get_state') {
        if (options.state) return { type: 'response', success: true, data: options.state };
        return {
          type: 'response',
          success: true,
          data: { model: { piframeContextPolicy: { limit: null, percent: 2.5 } } }
        };
      }
      return { type: 'response', success: true, data: {} };
    }
  });
  const registry = fakeRegistry({
    getSession: (id: string) => (id === session.id ? session : undefined),
    ensureWorkerForSession: async () => worker,
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
    send: (message) => sent.push(parseSent(message)) > 0
  });
  let counter = 0;
  const run = async (type: PcpCommandType, payload: Record<string, unknown>, isRemote = false) => {
    conn.isRemote = isRemote;
    counter += 1;
    const start = sent.length;
    await dispatcher.handle(
      conn,
      commandEnvelope(type, payload, { id: `m${counter}`, commandId: `cmd_${counter}`, sessionId: session.id })
    );
    return sent.slice(start).find((message) => message.kind === 'result');
  };
  return { workerCalls, session, run };
}

test('/reload runs the internal reload command and reapplies the policy, never sending text to the model', async () => {
  const { workerCalls, run } = fixture();
  const result = await run('agent.prompt', { text: '/reload' });
  assert.equal(at(result, 'payload', 'state'), 'completed');
  const prompts = workerCalls.filter((call) => call.command === 'prompt').map((call) => call.arguments?.message);
  assert.equal(prompts[0], '/piframe-reload');
  assert.ok(prompts.every((message) => message !== '/reload'));
  assert.ok(prompts.some((message) => message.startsWith('/piframe-context-policy ')));
});

test('/reload is refused while the agent is streaming instead of queuing text', async () => {
  const { workerCalls, run } = fixture({ streaming: true });
  const result = await run('agent.prompt', { text: '/reload', streamingBehavior: 'steer' });
  assert.notEqual(at(result, 'payload', 'state'), 'completed');
  assert.equal(workerCalls.length, 0);
});

test('ordinary prompts still go to the model unchanged', async () => {
  const { workerCalls, run } = fixture();
  await run('agent.prompt', { text: 'please reload the config file' });
  assert.deepEqual(
    workerCalls.filter((call) => call.command === 'prompt').map((call) => call.arguments?.message),
    ['please reload the config file']
  );
});

test('a prompt Pi rejects as already processing is queued as a follow-up instead of failing', async () => {
  const { workerCalls, run } = fixture({ piStillBusy: true });
  const result = await run('agent.prompt', { text: 'continua il merge' });
  assert.equal(at(result, 'payload', 'state'), 'completed');
  const follow = workerCalls.filter((call) => call.command === 'follow_up');
  assert.equal(follow.length, 1);
  assert.equal(follow[0]?.arguments?.message, 'continua il merge');
});

test('steer and follow-up go through Pi prompt so Pi queues or starts a run itself', async () => {
  const { workerCalls, run } = fixture({ streaming: true });
  await run('agent.prompt', { text: 'cambia approccio', streamingBehavior: 'steer' });
  await run('agent.prompt', { text: 'poi committa', streamingBehavior: 'followUp' });
  assert.deepEqual(
    workerCalls.map((call) => [call.command, call.arguments?.message, call.arguments?.streamingBehavior]),
    [
      ['prompt', 'cambia approccio', 'steer'],
      ['prompt', 'poi committa', 'followUp']
    ]
  );
});

test('a message sent during compaction waits for it to end instead of failing in Pi', async () => {
  const { workerCalls, session, run } = fixture();
  session.isCompacting = true;
  let compactionEndedAt = 0;
  setTimeout(() => {
    session.isCompacting = false;
    compactionEndedAt = Date.now();
  }, 300);
  const result = await run('agent.prompt', { text: 'aggiungi i test', streamingBehavior: 'steer' });
  assert.equal(at(result, 'payload', 'state'), 'completed');
  assert.ok(compactionEndedAt > 0, 'prompt was forwarded before compaction ended');
  assert.deepEqual(
    workerCalls.map((call) => call.arguments?.message),
    ['aggiungi i test']
  );
});

test('switching model drops the previous model context limit instead of carrying it over', async () => {
  const { workerCalls, session, run } = fixture();
  Object.assign(session, {
    model: { provider: 'anthropic', id: 'haiku', contextWindow: 100000 },
    contextWindowOverride: 100000,
    compactionReservePercent: 2.5
  });
  const result = await run('agent.setModel', { provider: 'anthropic', modelId: 'opus' });
  assert.equal(at(result, 'payload', 'state'), 'completed');
  assert.equal(session.contextWindowOverride, null);
  const policy = workerCalls.find((call) => call.command === 'prompt')?.arguments?.message;
  assert.equal(policy, '/piframe-context-policy {"limit":null,"percent":2.5}');
});

test('session stats show the post-compaction estimate while Pi reports context tokens as unknown', async () => {
  const { session, run } = fixture({
    state: { model: { contextWindow: 200000, piframeContextUsage: { tokens: null } } }
  });
  Object.assign(session, { contextWindowOverride: null, postCompactionTokens: 50000 });
  const result = await run('session.getStats', {});
  assert.deepEqual(at(result, 'payload', 'data', 'contextUsage'), {
    tokens: 50000,
    contextWindow: 200000,
    percent: 25
  });
});

test('agent.getCommands returns every Pi built-in before extension commands', async () => {
  const { run } = fixture();
  const result = await run('agent.getCommands', {});
  assert.equal(at(result, 'payload', 'state'), 'completed');
  const commands = commandsOf(result);
  const builtinNames = commands.filter((command) => command.source === 'builtin').map((command) => command.name);
  assert.deepEqual(builtinNames, [
    'settings',
    'model',
    'tree',
    'thinking',
    'scoped-models',
    'export',
    'import',
    'share',
    'bug',
    'copy',
    'name',
    'session',
    'changelog',
    'hotkeys',
    'fork',
    'clone',
    'trust',
    'login',
    'logout',
    'new',
    'compact',
    'resume',
    'reload',
    'quit'
  ]);
  assert.equal(commands.at(-1)?.name, 'caveman');
  assert.equal(
    commands.some((command) => command.name.startsWith('piframe-')),
    false
  );
  assert.equal(commands.find((command) => command.name === 'model')?.argumentHint, '<provider/model>');
});

test('/login and /logout run the local Pi auth actions without sending those built-ins to the model', async () => {
  const { workerCalls, run } = fixture();
  const login = await run('agent.authLogin', {});
  assert.equal(at(login, 'payload', 'state'), 'completed');
  assert.deepEqual(
    workerCalls.filter((call) => call.command === 'prompt').map((call) => call.arguments?.message),
    [`/piframe-auth-login ${JSON.stringify({ deviceId: fs.readFileSync(path.join(home, 'auth-device-id'), 'utf8') })}`]
  );
  assert.match(fs.readFileSync(path.join(home, 'auth-device-id'), 'utf8'), /^[0-9a-f-]{36}$/i);

  const logout = await run('agent.authLogout', {});
  assert.equal(at(logout, 'payload', 'state'), 'completed');
  assert.equal(
    workerCalls.filter((call) => call.command === 'prompt').at(-1)?.arguments?.message,
    '/piframe-auth-logout'
  );
  assert.equal(
    workerCalls.some((call) => call.arguments?.message === '/login' || call.arguments?.message === '/logout'),
    false
  );
});

test('auth built-ins are refused while the agent is streaming', async () => {
  const { workerCalls, run } = fixture({ streaming: true });
  const result = await run('agent.authLogin', {});
  assert.notEqual(at(result, 'payload', 'state'), 'completed');
  assert.equal(workerCalls.length, 0);
});

test('remote controls cannot claim PiFrame auth secret prompts', async () => {
  const { session, run } = fixture();
  const localOnly = new Set<string>();
  session.uiBroker = fakeUiBroker({
    addRequest: (request) => {
      if (request.localOnly && typeof request.requestId === 'string') localOnly.add(request.requestId);
    },
    isLocalOnly: (requestId: string) => localOnly.has(requestId)
  });
  session.uiBroker.addRequest({
    requestId: 'auth-secret',
    method: 'input',
    placeholder: 'piframe-secret:API key',
    localOnly: true
  });
  const result = await run('ui.claim', { requestId: 'auth-secret' }, true);
  assert.notEqual(at(result, 'payload', 'state'), 'completed');
  assert.equal(session.uiBroker.isLocalOnly('auth-secret'), true);
});

test('native built-in commands are never forwarded as model prompts', async () => {
  const { workerCalls, run } = fixture();
  const result = await run('agent.prompt', { text: '/settings' });
  assert.equal(at(result, 'payload', 'state'), 'rejected');
  assert.match(String(at(result, 'payload', 'error')), /Pi built-in command/);
  assert.equal(
    workerCalls.some((call) => call.command === 'prompt'),
    false
  );
});
