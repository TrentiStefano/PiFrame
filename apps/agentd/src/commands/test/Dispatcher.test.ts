import test from 'node:test';
import * as assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { execFileSync } from 'node:child_process';

const temporaryHome = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-dispatcher-test-'));
const previousHome = process.env.PI_CRUST_HOME;
process.env.PI_CRUST_HOME = temporaryHome;
test.after(() => {
  if (previousHome === undefined) delete process.env.PI_CRUST_HOME;
  else process.env.PI_CRUST_HOME = previousHome;
  fs.rmSync(temporaryHome, { recursive: true, force: true });
});
import { Dispatcher } from '../Dispatcher.js';
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

function createTestSetup(piPackages?: PiPackageOperations) {
  const manager = new ConnectionManager();
  const registry = new SessionRegistry({
    piExecutablePath: 'node',
    capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 60000,
    connectionManager: manager
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
  git(['config', 'user.name', 'Pi Crust Test']);
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
