import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { execFileSync } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { Dispatcher } from '../Dispatcher.js';
import { SessionRegistry } from '../../sessions/SessionRegistry.js';
import { ConnectionManager } from '../../server/wsServer.js';
import { Connection } from '../../server/connection.js';
import { RemoteManager } from '../../remote/RemoteManager.js';
import { RemoteAuthManager } from '../../remote/RemoteAuthManager.js';

class MockWebSocket extends EventEmitter {
  public sentMessages: string[] = [];
  public readyState = 1;
  public closeCode?: number;
  public closeReason?: string;

  send(data: string, cb?: () => void): void {
    this.sentMessages.push(data);
    if (cb) cb();
  }

  close(code?: number, reason?: string): void {
    this.readyState = 3;
    this.closeCode = code;
    this.closeReason = reason;
    this.emit('close');
  }
}

function createGitRepo(): { root: string; cleanup: () => void } {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-dispatcher-branch-repo-'));
  const git = (args: string[]) =>
    execFileSync('git', args, { cwd: root, encoding: 'utf8' });
  git(['init', '-q', '-b', 'main']);
  git(['config', 'user.email', 'test@example.com']);
  git(['config', 'user.name', 'PiFrame Test']);
  git(['config', 'core.autocrlf', 'false']);
  fs.writeFileSync(path.join(root, 'file.txt'), 'initial\n');
  git(['add', 'file.txt']);
  git(['commit', '-qm', 'initial']);
  git(['branch', 'feature']);
  return { root, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

function getLastSent(ws: MockWebSocket): any {
  if (ws.sentMessages.length === 0) return null;
  return JSON.parse(ws.sentMessages[ws.sentMessages.length - 1]);
}

function getSentResults(ws: MockWebSocket): any[] {
  return ws.sentMessages.map((m) => JSON.parse(m));
}

test('Dispatcher: branch commands remote permissions (view allowed for list, forbidden for switch; control allowed for switch)', async () => {
  const repo = createGitRepo();
  const remoteDbDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-remote-branch-test-'));
  const devicesPath = path.join(remoteDbDir, 'remote_devices.json');

  try {
    const manager = new ConnectionManager();
    const registry = new SessionRegistry({
      piExecutablePath: 'node',
      capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
      workerIdleTimeoutMs: 60000,
      connectionManager: manager,
    });
    const session = await registry.createSession({ cwd: repo.root });

    const authManager = new RemoteAuthManager(devicesPath);
    const remoteManager = new RemoteManager(undefined, authManager);
    remoteManager.setListenerPort(55555);

    const dispatcher = new Dispatcher(registry, manager, undefined, remoteManager);

    // Pair a device in 'view' mode
    const viewPairing = authManager.generatePairing(60000);
    const viewDevice = authManager.pair(viewPairing.secret, 'View Device', '127.0.0.1', 'view');

    // Create remote connection in 'view' mode
    const viewWs = new MockWebSocket();
    const viewConn = new Connection({
      ws: viewWs as any,
      expectedToken: 'tok',
      daemonVersion: '0.1.0',
      startedAt: Date.now(),
      piInfo: { path: 'node', version: '0.85.1', supported: true },
      remoteManager,
      onCommand: async () => {},
      onClose: () => {},
    });
    viewConn.state = 'ready';
    viewConn.isRemote = true;
    viewConn.deviceId = viewDevice.deviceId;

    // 1. workspace.listBranches in 'view' mode -> ALLOWED
    await dispatcher.handle(viewConn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_lb_view',
      ts: Date.now(),
      commandId: 'c_lb_view',
      type: 'workspace.listBranches',
      sessionId: session.id,
      payload: {},
    });
    const lbResult = getLastSent(viewWs);
    assert.equal(lbResult.kind, 'result');
    assert.equal(lbResult.payload.state, 'completed');
    assert.equal(lbResult.payload.data.currentBranch, 'main');
    assert.ok(Array.isArray(lbResult.payload.data.branches));

    // 2. workspace.switchBranch in 'view' mode -> FORBIDDEN
    await dispatcher.handle(viewConn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_sb_view',
      ts: Date.now(),
      commandId: 'c_sb_view',
      type: 'workspace.switchBranch',
      sessionId: session.id,
      payload: { branch: 'feature' },
    });
    const viewSent = getSentResults(viewWs);
    const errIdx = viewSent.findIndex((m) => m.kind === 'error');
    const resIdx = viewSent.findIndex((m) => m.kind === 'result' && m.payload?.state === 'rejected');
    assert.ok(errIdx !== -1, 'Expected error envelope');
    assert.ok(resIdx !== -1, 'Expected rejected result envelope');
    assert.ok(errIdx < resIdx, 'Error envelope must precede rejected result envelope');
    assert.equal(viewSent[errIdx].payload.code, 'REMOTE_FORBIDDEN');

    // Pair a device in 'control' mode
    const ctrlPairing = authManager.generatePairing(60000);
    const ctrlDevice = authManager.pair(ctrlPairing.secret, 'Control Device', '127.0.0.1', 'control');

    // Create remote connection in 'control' mode
    const ctrlWs = new MockWebSocket();
    const ctrlConn = new Connection({
      ws: ctrlWs as any,
      expectedToken: 'tok',
      daemonVersion: '0.1.0',
      startedAt: Date.now(),
      piInfo: { path: 'node', version: '0.85.1', supported: true },
      remoteManager,
      onCommand: async () => {},
      onClose: () => {},
    });
    ctrlConn.state = 'ready';
    ctrlConn.isRemote = true;
    ctrlConn.deviceId = ctrlDevice.deviceId;

    // 3. workspace.switchBranch in 'control' mode -> ALLOWED
    await dispatcher.handle(ctrlConn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_sb_ctrl',
      ts: Date.now(),
      commandId: 'c_sb_ctrl',
      type: 'workspace.switchBranch',
      sessionId: session.id,
      payload: { branch: 'feature' },
    });
    const sbCtrlResult = getLastSent(ctrlWs);
    assert.equal(sbCtrlResult.kind, 'result');
    assert.equal(sbCtrlResult.payload.state, 'completed');
    assert.equal(sbCtrlResult.payload.data.currentBranch, 'feature');
  } finally {
    repo.cleanup();
    fs.rmSync(remoteDbDir, { recursive: true, force: true });
  }
});

test('Dispatcher: switchBranch is rejected while session is read-only or busy', async () => {
  const repo = createGitRepo();
  try {
    const manager = new ConnectionManager();
    const registry = new SessionRegistry({
      piExecutablePath: 'node',
      capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
      workerIdleTimeoutMs: 60000,
      connectionManager: manager,
    });
    const session = await registry.createSession({ cwd: repo.root });
    const dispatcher = new Dispatcher(registry, manager);

    const ws = new MockWebSocket();
    const conn = new Connection({
      ws: ws as any,
      expectedToken: 'tok',
      daemonVersion: '0.1.0',
      startedAt: Date.now(),
      piInfo: { path: 'node', version: '0.85.1', supported: true },
      onCommand: async () => {},
      onClose: () => {},
    });
    conn.state = 'ready';

    // 1. Read-only session
    session.readOnly = true;
    await dispatcher.handle(conn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_ro_switch',
      ts: Date.now(),
      commandId: 'c_ro_switch',
      type: 'workspace.switchBranch',
      sessionId: session.id,
      payload: { branch: 'feature' },
    });
    let sent = getSentResults(ws);
    let err = sent.find((m) => m.kind === 'error' && m.commandId === 'c_ro_switch');
    let res = sent.find((m) => m.kind === 'result' && m.commandId === 'c_ro_switch');
    assert.ok(err, 'Expected error envelope');
    assert.ok(res, 'Expected result envelope');
    assert.ok(sent.indexOf(err) < sent.indexOf(res), 'Error envelope must precede result envelope');
    assert.equal(err.payload.code, 'COMMAND_REJECTED');
    assert.ok(err.payload.message.includes('read-only'));

    // listBranches is still permitted for read-only session
    await dispatcher.handle(conn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_ro_list',
      ts: Date.now(),
      commandId: 'c_ro_list',
      type: 'workspace.listBranches',
      sessionId: session.id,
      payload: {},
    });
    let last = getLastSent(ws);
    assert.equal(last.kind, 'result');
    assert.equal(last.payload.state, 'completed');

    session.readOnly = false;

    // 2. Active streaming session
    session.isStreaming = true;
    await dispatcher.handle(conn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_busy_switch',
      ts: Date.now(),
      commandId: 'c_busy_switch',
      type: 'workspace.switchBranch',
      sessionId: session.id,
      payload: { branch: 'feature' },
    });
    sent = getSentResults(ws);
    err = sent.find((m) => m.kind === 'error' && m.commandId === 'c_busy_switch');
    res = sent.find((m) => m.kind === 'result' && m.commandId === 'c_busy_switch');
    assert.ok(err, 'Expected error envelope');
    assert.ok(res, 'Expected result envelope');
    assert.ok(sent.indexOf(err) < sent.indexOf(res), 'Error envelope must precede result envelope');
    assert.equal(err.payload.code, 'COMMAND_REJECTED');
    assert.ok(err.payload.message.includes('Pi worker is active'));
    session.isStreaming = false;

    // 3. Active tools running
    session.activeTools.set('tool_1', { isRunning: true } as any);
    await dispatcher.handle(conn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_tool_switch',
      ts: Date.now(),
      commandId: 'c_tool_switch',
      type: 'workspace.switchBranch',
      sessionId: session.id,
      payload: { branch: 'feature' },
    });
    sent = getSentResults(ws);
    err = sent.find((m) => m.kind === 'error' && m.commandId === 'c_tool_switch');
    res = sent.find((m) => m.kind === 'result' && m.commandId === 'c_tool_switch');
    assert.ok(err, 'Expected error envelope');
    assert.ok(res, 'Expected result envelope');
    assert.ok(sent.indexOf(err) < sent.indexOf(res), 'Error envelope must precede result envelope');
    assert.equal(err.payload.code, 'COMMAND_REJECTED');
    session.activeTools.clear();

    // 4. Session status in working / compacting / awaiting_user
    session.status = 'working';
    await dispatcher.handle(conn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_working_switch',
      ts: Date.now(),
      commandId: 'c_working_switch',
      type: 'workspace.switchBranch',
      sessionId: session.id,
      payload: { branch: 'feature' },
    });
    sent = getSentResults(ws);
    err = sent.find((m) => m.kind === 'error' && m.commandId === 'c_working_switch');
    res = sent.find((m) => m.kind === 'result' && m.commandId === 'c_working_switch');
    assert.ok(err, 'Expected error envelope');
    assert.ok(res, 'Expected result envelope');
    assert.ok(sent.indexOf(err) < sent.indexOf(res), 'Error envelope must precede result envelope');
    assert.equal(err.payload.code, 'COMMAND_REJECTED');
    session.status = 'idle';

    // 5. Normal idle writable session succeeds
    await dispatcher.handle(conn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_idle_switch',
      ts: Date.now(),
      commandId: 'c_idle_switch',
      type: 'workspace.switchBranch',
      sessionId: session.id,
      payload: { branch: 'feature' },
    });
    last = getLastSent(ws);
    assert.equal(last.kind, 'result');
    assert.equal(last.payload.state, 'completed');
    assert.equal(last.payload.data.currentBranch, 'feature');
  } finally {
    repo.cleanup();
  }
});
