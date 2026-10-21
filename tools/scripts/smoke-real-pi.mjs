import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { discoverPi } from '../../apps/agentd/dist/pi/discovery.js';
import { StdioPiTransport } from '../../apps/agentd/dist/pi/StdioPiTransport.js';
import { SessionRegistry } from '../../apps/agentd/dist/sessions/SessionRegistry.js';
import { SessionIndex } from '../../apps/agentd/dist/sessions/SessionIndex.js';

// Real Pi CLI, isolated persistence, and a loopback-only mock model. No real LLM calls or user session writes.
const repo = process.cwd();
const installation = await discoverPi(process.env.PI_FRAME_REAL_PI_PATH);
assert.ok(installation.found && installation.supported, installation.hint || 'Install a supported Pi CLI');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-real-smoke-'));
const workspaceDir = path.join(repo, `.piframe-smoke-${process.pid}`);
fs.mkdirSync(workspaceDir);
const agentDir = path.join(directory, 'agent');
fs.mkdirSync(agentDir);
let calls = 0;
const server = http.createServer((request, response) => {
  if (request.method !== 'POST' || !request.url.endsWith('/chat/completions')) {
    response.writeHead(404).end();
    return;
  }
  calls++;
  request.resume();
  request.on('end', () => {
    response.writeHead(200, { 'Content-Type': 'text/event-stream' });
    const chunk = (delta, finish_reason = null) => ({
      id: 'smoke', object: 'chat.completion.chunk', created: 1, model: 'smoke',
      choices: [{ index: 0, delta, finish_reason }],
    });
    for (const frame of [chunk({ role: 'assistant' }), chunk({ content: 'Real Pi transport works.' }), chunk({}, 'stop')]) {
      response.write(`data: ${JSON.stringify(frame)}\n\n`);
    }
    response.end('data: [DONE]\n\n');
  });
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
fs.writeFileSync(path.join(agentDir, 'models.json'), JSON.stringify({ providers: {
  'frame-smoke': {
    baseUrl: `http://127.0.0.1:${server.address().port}/v1`, api: 'openai-completions', apiKey: 'local-test-only',
    models: [{ id: 'smoke', name: 'Smoke', reasoning: false, input: ['text'], contextWindow: 32000, maxTokens: 512,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }],
  },
} }));
fs.writeFileSync(path.join(agentDir, 'settings.json'), JSON.stringify({
  defaultProvider: 'frame-smoke', defaultModel: 'smoke', packages: [],
}));
const env = { PI_CODING_AGENT_DIR: agentDir, PI_OFFLINE: '1' };
const previousEnv = Object.fromEntries(['PI_CODING_AGENT_DIR', 'PI_OFFLINE', 'PI_FRAME_HOME'].map((key) => [key, process.env[key]]));
let registry;
let onEvent;
let transport;
try {
  transport = new StdioPiTransport({ executablePath: installation.path });
  await transport.start({ cwd: workspaceDir, env, args: [
    '--mode', 'rpc', '--offline', '--no-extensions', '--no-skills', '--no-prompt-templates',
    '--provider', 'frame-smoke', '--model', 'smoke', '--session-dir', path.join(agentDir, 'sessions'),
    '--session-id', 'frame-smoke-session',
  ] });
  const state = (await transport.send({ command: 'get_state' })).data;
  assert.equal(state.model.provider, 'frame-smoke');
  const events = [];
  const settled = (async () => {
    for await (const event of transport.events()) {
      events.push(event);
      if (event.type === 'agent_settled') return;
    }
    throw new Error('Pi exited before settlement');
  })();
  const prompt = await transport.send({ command: 'prompt', arguments: { message: 'Reply once without tools.' } });
  assert.equal(prompt.success, true);
  await Promise.race([settled, new Promise((_, reject) => {
    const deadline = setTimeout(() => reject(new Error('Real Pi smoke timed out')), 15000);
    deadline.unref();
  })]);
  assert.equal(calls, 1);
  assert.ok(events.some((e) => e.type === 'message_update' && e.assistantMessageEvent?.delta === 'Real Pi transport works.'));
  const history = (await transport.send({ command: 'get_entries' })).data;
  assert.ok(history.entries.some((e) => e.message?.role === 'assistant'));
  const saved = (await transport.send({ command: 'get_state' })).data.sessionFile;
  assert.ok(saved && fs.existsSync(saved));
  await assert.rejects(transport.send({ command: 'set_model', arguments: { provider: 'does-not-exist', modelId: 'invalid' } }));
  await transport.stop({ graceMs: 1000 });
  transport = new StdioPiTransport({ executablePath: installation.path });
  await transport.start({ cwd: workspaceDir, env, args: [
    '--mode', 'rpc', '--offline', '--no-extensions', '--no-skills', '--no-prompt-templates', '--session', saved,
  ] });
  const restored = (await transport.send({ command: 'get_entries' })).data;
  assert.equal(restored.entries.length, history.entries.length);
  await transport.stop({ graceMs: 1000 });
  process.env.PI_CODING_AGENT_DIR = agentDir;
  process.env.PI_OFFLINE = '1';
  process.env.PI_FRAME_HOME = path.join(directory, 'frame');
  registry = new SessionRegistry({
    piExecutablePath: installation.path,
    capabilities: { version: installation.version, supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 0,
    connectionManager: { broadcast: (id, event) => onEvent?.(id, event) },
    sessionIndex: new SessionIndex({ sessionsDir: path.join(agentDir, 'sessions') }),
  });
  const external = await registry.openSession('frame-smoke-session');
  assert.equal(external.entries.length, 2);
  const originalBytes = fs.readFileSync(saved);
  const clone = await registry.cloneSession(external.id);
  assert.notEqual(clone.sessionFile, saved);
  assert.equal(clone.entries.length, 2);
  const fork = await registry.cloneSession(external.id, history.entries.find((e) => e.message?.role === 'user').id);
  assert.notEqual(fork.sessionFile, saved);
  const forkWorker = await registry.ensureWorkerForSession(fork.id);
  const forkSettled = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Fork did not settle')), 15000);
    onEvent = (id, event) => {
      if (id === fork.id && event.type === 'run.settled') { clearTimeout(timeout); resolve(); }
    };
  });
  await forkWorker.send({ command: 'prompt', arguments: { message: 'Persist the fork with one response.' } });
  await forkSettled;
  const finalHeader = JSON.parse(fs.readFileSync(fork.sessionFile, 'utf8').split('\n')[0]);
  assert.equal(fork.id, finalHeader.id);
  const list = await registry.listSessions(undefined, 1000);
  assert.equal(list.filter((item) => item.sessionFile === fork.sessionFile).length, 1);
  assert.deepEqual(fs.readFileSync(saved), originalBytes);
  console.log(`Pi ${installation.version}: prompt, stream, settlement, history, reopen, failure propagation, daemon clone/fork PASS (loopback mock model).`);
} finally {
  await registry?.closeAll();
  await transport?.stop({ graceMs: 1000 });
  for (const [key, value] of Object.entries(previousEnv)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(directory, { recursive: true, force: true });
  fs.rmSync(workspaceDir, { recursive: true, force: true });
}
