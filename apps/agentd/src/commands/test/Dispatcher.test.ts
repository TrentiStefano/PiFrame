import test from 'node:test';
import * as assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { execFileSync } from 'node:child_process';

const temporaryHome = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-dispatcher-test-'));
const previousHome = process.env.PI_FRAME_HOME;
process.env.PI_FRAME_HOME = temporaryHome;
test.after(() => {
  if (previousHome === undefined) delete process.env.PI_FRAME_HOME;
  else process.env.PI_FRAME_HOME = previousHome;
  fs.rmSync(temporaryHome, { recursive: true, force: true });
});
import { Dispatcher } from '../Dispatcher.js';
import { SessionIndex } from '../../sessions/SessionIndex.js';
import { SessionRegistry } from '../../sessions/SessionRegistry.js';
import { ConnectionManager } from '../../server/wsServer.js';
import { Connection } from '../../server/connection.js';
import type { PiPackageOperations } from '../../pi/PiPackageService.js';

class MockWebSocket extends EventEmitter {
  public readyState = 1;
  public sentMessages: string[] = [];
  public closedCode?: number;
  public closedReason?: string;

  public send(data: string, cb?: () => void): void {
    this.sentMessages.push(data);
    if (cb) cb();
  }

  public close(code: number, reason: string): void {
    this.readyState = 3;
    this.closedCode = code;
    this.closedReason = reason;
    this.emit('close');
  }
}

function createTestSetup(piPackages?: PiPackageOperations, sessionIndex?: SessionIndex) {
  const manager = new ConnectionManager();
  const registry = new SessionRegistry({
    piExecutablePath: 'node',
    capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 60000,
    connectionManager: manager,
    sessionIndex
  });
  const dispatcher = new Dispatcher(registry, manager, piPackages);

  const ws = new MockWebSocket();
  const conn = new Connection({
    ws: ws as any,
    expectedToken: 'tok',
    daemonVersion: '0.1.0',
    startedAt: Date.now(),
    piInfo: { path: 'node', version: '0.85.1', supported: true },
    onCommand: async () => {},
    onClose: () => {}
  });
  conn.state = 'ready';

  return { registry, manager, dispatcher, ws, conn };
}

function createGitRepo(): { root: string; cleanup: () => void } {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-dispatcher-repo-'));
  const git = (args: string[]) => execFileSync('git', args, { cwd: root, stdio: 'ignore' });
  git(['init', '-q']);
  git(['config', 'user.email', 'test@example.com']);
  git(['config', 'user.name', 'PiFrame Test']);
  git(['config', 'core.autocrlf', 'false']);
  fs.writeFileSync(path.join(root, 'file.txt'), 'original\n');
  git(['add', 'file.txt']);
  git(['commit', '-qm', 'initial']);
  return { root, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

async function sendCommand(setup: ReturnType<typeof createTestSetup>, type: string, sessionId: string | undefined, payload: Record<string, unknown> = {}) {
  const start = setup.ws.sentMessages.length;
  await setup.dispatcher.handle(setup.conn, {
    protocol: 1, kind: 'command', id: `msg_${start}`, ts: Date.now(), commandId: `workspace_${start}_${Math.random()}`,
    type, sessionId, payload
  } as any);
  return setup.ws.sentMessages.slice(start).map((item) => JSON.parse(item));
}

test('Dispatcher: session.list returns a cached result before slow filesystem revalidation', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-dispatcher-session-list-'));
  const sessionsDir = path.join(root, 'sessions');
  const cachePath = path.join(root, 'index.json');
  fs.mkdirSync(sessionsDir);
  fs.writeFileSync(path.join(sessionsDir, 'cached.jsonl'), [
    { type: 'session', id: 'cached', cwd: process.cwd() },
    { type: 'session_info', name: 'Cached session' },
  ].map((row) => JSON.stringify(row)).join('\n') + '\n');
  const index = new SessionIndex({ sessionsDir, cachePath });
  await index.scan();
  const currentIndex = new SessionIndex({ sessionsDir, cachePath });
  const enumerate = (currentIndex as any).enumerateSessionFiles.bind(currentIndex);
  let release!: () => void;
  const blocked = new Promise<void>((resolve) => { release = resolve; });
  (currentIndex as any).enumerateSessionFiles = async () => {
    await blocked;
    return enumerate();
  };
  const setup = createTestSetup(undefined, currentIndex);
  try {
    let timer: NodeJS.Timeout | undefined;
    const result = await Promise.race([
      sendCommand(setup, 'session.list', '@daemon'),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error('session.list waited for filesystem revalidation')), 1000);
      })
    ]);
    if (timer) clearTimeout(timer);
    assert.equal(result[0].kind, 'ack');
    assert.equal(result[1].payload.state, 'completed');
    assert.equal(result[1].payload.data.sessions[0].id, 'cached');
    release();
    await currentIndex.scanFast();
  } finally {
    release();
    await setup.registry.closeAll();
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('Dispatcher: workspace commands require session scope and ignore client cwd', async () => {
  const repoA = createGitRepo();
  const repoB = createGitRepo();
  try {
    const setup = createTestSetup();
    const session = await setup.registry.createSession({ cwd: repoA.root });
    const scoped = await sendCommand(setup, 'workspace.refresh', session.id, { cwd: repoB.root });
    assert.equal(path.normalize(scoped[1].payload.data.rootPath), path.normalize(fs.realpathSync(repoA.root)));
    const unscoped = await sendCommand(setup, 'workspace.refresh', undefined, { cwd: repoB.root });
    assert.equal(unscoped[1].payload.state, 'rejected');
  } finally {
    repoA.cleanup();
    repoB.cleanup();
  }
});

test('Dispatcher: workspace blocks writes for read-only and active sessions, but permits reads', async () => {
  const repo = createGitRepo();
  try {
    const setup = createTestSetup();
    const session = await setup.registry.createSession({ cwd: repo.root });
    const file = (await sendCommand(setup, 'workspace.readFile', session.id, { path: 'file.txt' }))[1].payload.data;
    fs.writeFileSync(path.join(repo.root, 'file.txt'), 'edited\n');
    session.worker = { health: () => ({ alive: true }) } as any; // healthy idle workers may still use the workspace
    session.readOnly = true;
    let result = await sendCommand(setup, 'workspace.saveFile', session.id, { path: 'file.txt', content: 'blocked', revision: file.revision });
    assert.equal(result[1].payload.state, 'rejected');
    assert.equal((await sendCommand(setup, 'workspace.listFiles', session.id))[1].payload.state, 'completed');
    session.readOnly = false;
    result = await sendCommand(setup, 'workspace.gitAction', session.id, { action: 'stage', paths: ['file.txt'] });
    assert.equal(result[1].payload.state, 'completed');
    session.isStreaming = true;
    result = await sendCommand(setup, 'workspace.gitAction', session.id, { action: 'unstage', paths: ['file.txt'] });
    assert.equal(result[1].payload.state, 'rejected');
    assert.equal(fs.readFileSync(path.join(repo.root, 'file.txt'), 'utf8'), 'edited\n');
  } finally {
    repo.cleanup();
  }
});

test('Dispatcher: workspace rejects traversal and symlink escape and surfaces Git write failures', async () => {
  const repo = createGitRepo();
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-dispatcher-outside-'));
  try {
    fs.writeFileSync(path.join(outside, 'secret.txt'), 'secret');
    fs.symlinkSync(outside, path.join(repo.root, 'outside-link'), 'junction');
    const setup = createTestSetup();
    const session = await setup.registry.createSession({ cwd: repo.root });
    let result = await sendCommand(setup, 'workspace.readFile', session.id, { path: '../secret.txt' });
    assert.equal(result[1].payload.state, 'rejected');
    result = await sendCommand(setup, 'workspace.readFile', session.id, { path: 'outside-link/secret.txt' });
    assert.equal(result[1].payload.state, 'rejected');
    result = await sendCommand(setup, 'workspace.gitAction', session.id, { action: 'stage', paths: ['missing.txt'] });
    assert.equal(result[1].payload.state, 'rejected');
    assert.match(result[1].payload.error, /stale/i);
  } finally {
    fs.rmSync(outside, { recursive: true, force: true });
    repo.cleanup();
  }
});

test('Dispatcher: workspace gitAction stages and commits confirmed staged paths', async () => {
  const repo = createGitRepo();
  try {
    const setup = createTestSetup();
    const session = await setup.registry.createSession({ cwd: repo.root });
    fs.writeFileSync(path.join(repo.root, 'file.txt'), 'committed by dispatcher\n');
    let result = await sendCommand(setup, 'workspace.gitAction', session.id, { action: 'stage', paths: ['file.txt'] });
    assert.equal(result[1].payload.state, 'completed');
    result = await sendCommand(setup, 'workspace.gitAction', session.id, {
      action: 'commit', paths: ['file.txt'], expectedStagedPaths: ['file.txt'], message: 'workspace edit'
    });
    assert.equal(result[1].payload.state, 'completed');
    assert.equal(result[1].payload.data.status.files.length, 0);
  } finally {
    repo.cleanup();
  }
});

test('Dispatcher: delegates Pi package list/update/remove/pin commands', async () => {
  const calls: string[] = [];
  const piPackages: PiPackageOperations = {
    async list() {
      calls.push('list');
      return [{ source: 'npm:pi-caveman', name: 'pi-caveman', version: '1.2.3', pinnedVersion: null }];
    },
    async update(source) {
      calls.push(`update:${source}`);
      return { output: 'updated' };
    },
    async remove(source) {
      calls.push(`remove:${source}`);
      return { output: 'removed' };
    },
    async pin(source, version) {
      calls.push(`pin:${source}@${version}`);
      return { output: 'pinned', source: `npm:pi-caveman@${version}` };
    },
  };
  const setup = createTestSetup(piPackages);
  const listed = await sendCommand(setup, 'pi.packages.list', undefined);
  assert.equal(listed[1].payload.data.packages[0].name, 'pi-caveman');
  assert.equal((await sendCommand(setup, 'pi.packages.update', undefined, { source: 'npm:pi-caveman' }))[1].payload.state, 'completed');
  assert.equal((await sendCommand(setup, 'pi.packages.remove', undefined, { source: 'npm:pi-caveman' }))[1].payload.state, 'completed');
  const pinned = await sendCommand(setup, 'pi.packages.pin', undefined, { source: 'npm:pi-caveman', version: '1.2.3' });
  assert.equal(pinned[1].payload.data.source, 'npm:pi-caveman@1.2.3');
  assert.deepEqual(calls, ['list', 'update:npm:pi-caveman', 'remove:npm:pi-caveman', 'pin:npm:pi-caveman@1.2.3']);
});

test('Dispatcher: executes daemon.getConfig and returns config', async () => {
  const { dispatcher, ws, conn } = createTestSetup();

  await dispatcher.handle(conn, {
    protocol: 1,
    kind: 'command',
    id: 'cmd_1',
    ts: Date.now(),
    commandId: 'c_get_cfg',
    type: 'daemon.getConfig',
    payload: {}
  });

  const ack = JSON.parse(ws.sentMessages[0]);
  assert.equal(ack.kind, 'ack');
  assert.equal(ack.payload.state, 'accepted');

  const res = JSON.parse(ws.sentMessages[1]);
  assert.equal(res.kind, 'result');
  assert.equal(res.payload.state, 'completed');
  assert.ok(res.payload.data.workerIdleTimeoutMs !== undefined);
});

test('Dispatcher: deduplicates repeated commands with identical commandId', async () => {
  const { dispatcher, ws, conn } = createTestSetup();

  // Send first command
  await dispatcher.handle(conn, {
    protocol: 1,
    kind: 'command',
    id: 'cmd_1',
    ts: Date.now(),
    commandId: 'c_unique_123',
    type: 'daemon.getConfig',
    payload: {}
  });

  assert.equal(ws.sentMessages.length, 2); // ack + result
  const firstResult = JSON.parse(ws.sentMessages[1]);
  assert.equal(firstResult.payload.state, 'completed');

  // Send exact same commandId again
  await dispatcher.handle(conn, {
    protocol: 1,
    kind: 'command',
    id: 'cmd_2',
    ts: Date.now(),
    commandId: 'c_unique_123',
    type: 'daemon.getConfig',
    payload: {}
  });

  assert.equal(ws.sentMessages.length, 4); // second ack + second result
  const secondResult = JSON.parse(ws.sentMessages[3]);
  assert.equal(secondResult.payload.state, 'deduplicated');
  assert.deepEqual(secondResult.payload.data, firstResult.payload.data);
});

test('Dispatcher: daemon.setConfig validates workerIdleTimeoutMs and updates runtime', async () => {
  const { dispatcher, ws, conn, registry } = createTestSetup();

  // Valid update to 5 minutes (300,000 ms)
  await dispatcher.handle(conn, {
    protocol: 1,
    kind: 'command',
    id: 'cmd_set',
    ts: Date.now(),
    commandId: 'c_set_cfg',
    type: 'daemon.setConfig',
    payload: { workerIdleTimeoutMs: 300000 }
  });

  const res = JSON.parse(ws.sentMessages[1]);
  assert.equal(res.payload.state, 'completed');
  assert.equal(res.payload.data.workerIdleTimeoutMs, 300000);

  // Invalid update: negative timeout -> should reject
  await dispatcher.handle(conn, {
    protocol: 1,
    kind: 'command',
    id: 'cmd_set_inv',
    ts: Date.now(),
    commandId: 'c_set_cfg_inv',
    type: 'daemon.setConfig',
    payload: { workerIdleTimeoutMs: -100 }
  });

  const errRes = JSON.parse(ws.sentMessages[3]);
  assert.equal(errRes.payload.state, 'rejected');
});

test('Dispatcher: executes remote.* commands and enforces remote allowlist', async () => {
  const { RemoteManager } = await import('../../remote/RemoteManager.js');
  const { RemoteAuthManager } = await import('../../remote/RemoteAuthManager.js');
  const manager = new ConnectionManager();
  const registry = new SessionRegistry({
    piExecutablePath: 'node',
    capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 60000,
    connectionManager: manager
  });

  const devFile = path.join(os.tmpdir(), `pi_remote_disp_${Date.now()}.json`);
  const authManager = new RemoteAuthManager(devFile);
  const remoteManager = new RemoteManager(undefined, authManager);
  const dispatcher = new Dispatcher(registry, manager, undefined, remoteManager);

  // Set fake listener port so remoteManager can start
  remoteManager.setListenerPort(55555);

  const ws = new MockWebSocket();
  const conn = new Connection({
    ws: ws as any,
    expectedToken: 'tok',
    daemonVersion: '0.1.0',
    startedAt: Date.now(),
    piInfo: { path: 'node', version: '0.85.1', supported: true },
    onCommand: async () => {},
    onClose: () => {}
  });
  conn.state = 'ready';

  function getLastResult(mockWs: MockWebSocket): any {
    for (let i = mockWs.sentMessages.length - 1; i >= 0; i--) {
      const msg = JSON.parse(mockWs.sentMessages[i]);
      if (msg.kind === 'result') return msg;
    }
    return null;
  }

  // 1. remote.getStatus
  await dispatcher.handle(conn, {
    protocol: 1, kind: 'command', id: 'cmd_rg', ts: Date.now(),
    commandId: 'c_rem_get', type: 'remote.getStatus', payload: {}
  });
  const res1 = getLastResult(ws);
  assert.equal(res1.payload.state, 'completed');
  assert.equal(res1.payload.data.enabled, false);

  // 2. remote.setOptions
  await dispatcher.handle(conn, {
    protocol: 1, kind: 'command', id: 'cmd_opt', ts: Date.now(),
    commandId: 'c_rem_opt', type: 'remote.setOptions', payload: { defaultMode: 'control' }
  });
  const res2 = getLastResult(ws);
  assert.equal(res2.payload.state, 'completed');
  assert.equal(res2.payload.data.options.defaultMode, 'control');

  // Pair a test device
  const pairing = authManager.generatePairing(60000);
  const paired = authManager.pair(pairing.secret, 'Test Client', '127.0.0.1', 'view');

  // 3. Remote connection in 'view' mode:
  const remoteWs = new MockWebSocket();
  const remoteConn = new Connection({
    ws: remoteWs as any,
    expectedToken: 'tok',
    daemonVersion: '0.1.0',
    startedAt: Date.now(),
    piInfo: { path: 'node', version: '0.85.1', supported: true },
    remoteManager,
    onCommand: async () => {},
    onClose: () => {}
  });
  remoteConn.state = 'ready';
  remoteConn.isRemote = true;
  remoteConn.deviceId = paired.deviceId;

  // Remote attempts remote.* -> MUST BE BLOCKED
  await dispatcher.handle(remoteConn, {
    protocol: 1, kind: 'command', id: 'cmd_rem_att', ts: Date.now(),
    commandId: 'c_rem_att', type: 'remote.getStatus', payload: {}
  });
  const res3 = getLastResult(remoteWs);
  assert.equal(res3.payload.state, 'rejected');
  assert.ok(res3.payload.error.includes('not permitted'));

  // Remote attempts daemon.setConfig -> MUST BE BLOCKED
  await dispatcher.handle(remoteConn, {
    protocol: 1, kind: 'command', id: 'cmd_cfg_att', ts: Date.now(),
    commandId: 'c_cfg_att', type: 'daemon.setConfig', payload: { workerIdleTimeoutMs: 5000 }
  });
  const res4 = getLastResult(remoteWs);
  assert.equal(res4.payload.state, 'rejected');

  // Remote attempts pi.packages.* -> MUST BE BLOCKED
  await dispatcher.handle(remoteConn, {
    protocol: 1, kind: 'command', id: 'cmd_pkg_att', ts: Date.now(),
    commandId: 'c_pkg_att', type: 'pi.packages.list', payload: {}
  });
  const res5 = getLastResult(remoteWs);
  assert.equal(res5.payload.state, 'rejected');

  // Remote in view mode attempts workspace.saveFile -> MUST BE BLOCKED
  await dispatcher.handle(remoteConn, {
    protocol: 1, kind: 'command', id: 'cmd_write_blocked', ts: Date.now(),
    commandId: 'c_blk_write', type: 'workspace.saveFile',
    payload: { path: 'a.txt', content: 'hello', revision: '0'.repeat(64) }
  });
  const res6 = getLastResult(remoteWs);
  assert.equal(res6.payload.state, 'rejected');

  // Remote in view mode attempts agent.prompt -> MUST BE BLOCKED
  await dispatcher.handle(remoteConn, {
    protocol: 1, kind: 'command', id: 'cmd_prompt_blocked', ts: Date.now(),
    commandId: 'c_blk_prompt', type: 'agent.prompt',
    payload: { text: 'hello' }, sessionId: 'sess_1'
  });
  const res7 = getLastResult(remoteWs);
  assert.equal(res7.payload.state, 'rejected');

  // Local connection attempts daemon.setConfig { remote: ... } -> MUST BE BLOCKED with CONFIG_INVALID
  await dispatcher.handle(conn, {
    protocol: 1, kind: 'command', id: 'cmd_inj_cfg', ts: Date.now(),
    commandId: 'c_inj_cfg', type: 'daemon.setConfig',
    payload: { remote: { customTunnelCommand: 'calc.exe' } }
  });
  const res8 = getLastResult(ws);
  assert.equal(res8.payload.state, 'rejected');
  assert.ok(res8.payload.error.includes('cannot modify "remote"'));

  try { fs.unlinkSync(devFile); } catch {}
});

test('Dispatcher: agent.interrupt clears queues without marking the worker idle', async () => {
  const setup = createTestSetup();
  const session = await setup.registry.createSession({ cwd: os.tmpdir() });
  session.queue = { steering: ['queued steer 1'], followUp: ['queued follow-up 2'] };
  session.status = 'working';
  session.isStreaming = true;
  const commands: string[] = [];
  session.worker = {
    send: async ({ command }: { command: string }) => {
      commands.push(command);
      return { data: {} };
    },
  } as any;

  const res = await sendCommand(setup, 'agent.interrupt', session.id);
  const resultMsg = res.find((m: any) => m.kind === 'result');
  assert.ok(resultMsg, 'must receive result');
  assert.equal(resultMsg.payload.state, 'completed');
  assert.equal(resultMsg.payload.data.interrupted, true);
  assert.deepEqual(resultMsg.payload.data.queue, { steering: [], followUp: [] });
  assert.deepEqual(session.queue, { steering: [], followUp: [] });
  assert.deepEqual(commands, ['clear_queue', 'abort']);
  assert.equal(session.status, 'working');
  assert.equal(session.isStreaming, true);
  await setup.registry.closeAll();
});

test('Dispatcher: agent.interrupt responds before Pi finishes becoming idle', { timeout: 10_000 }, async () => {
  const setup = createTestSetup();
  const session = await setup.registry.createSession({ cwd: os.tmpdir() });
  session.status = 'working';
  session.isStreaming = true;
  let releaseAbort!: () => void;
  const abortPending = new Promise<void>((resolve) => { releaseAbort = resolve; });
  const commands: string[] = [];
  session.worker = {
    send: async ({ command }: { command: string }) => {
      commands.push(command);
      if (command === 'abort') await abortPending;
      return { data: {} };
    },
  } as any;

  const responsePromise = sendCommand(setup, 'agent.interrupt', session.id);
  try {
    const response = await Promise.race([
      responsePromise,
      new Promise<null>((resolve) => setTimeout(() => resolve(null), 500)),
    ]);
    assert.ok(response, 'interrupt response must not wait for Pi idle');
    const result = response.find((message: any) => message.kind === 'result');
    assert.equal(result.payload.state, 'completed');
    assert.deepEqual(commands, ['clear_queue', 'abort']);
    assert.equal(session.status, 'working');
    assert.equal(session.isStreaming, true);
  } finally {
    releaseAbort();
    await responsePromise;
    await setup.registry.closeAll();
  }
});

test('Dispatcher: session.getHistory paginates historical entries backwards', async () => {
  const setup = createTestSetup();
  const session = await setup.registry.createSession({ cwd: os.tmpdir() });
  for (let i = 1; i <= 120; i++) {
    session.entries.push({ id: `entry_${i}`, role: i % 2 === 0 ? 'assistant' : 'user', text: `Message ${i}` });
  }

  const res1 = await sendCommand(setup, 'session.getHistory', session.id, { beforeId: 'entry_100', limit: 30 });
  const result1 = res1.find((m: any) => m.kind === 'result');
  assert.ok(result1, 'must receive result');
  assert.equal(result1.payload.state, 'completed');
  assert.equal(result1.payload.data.entries.length, 30);
  assert.equal(result1.payload.data.entries[0].id, 'entry_70');
  assert.equal(result1.payload.data.entries[29].id, 'entry_99');
  assert.equal(result1.payload.data.hasMore, true);
  assert.equal(result1.payload.data.totalEntries, 120);

  const res2 = await sendCommand(setup, 'session.getHistory', session.id, { beforeId: 'entry_70', limit: 100 });
  const result2 = res2.find((m: any) => m.kind === 'result');
  assert.equal(result2.payload.data.entries.length, 69);
  assert.equal(result2.payload.data.entries[0].id, 'entry_1');
  assert.equal(result2.payload.data.hasMore, false);
});

