import test from 'node:test';
import * as assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import * as path from 'node:path';
import * as os from 'node:os';
import * as fs from 'node:fs';
import { Dispatcher } from '../../commands/Dispatcher.js';
import { SessionRegistry } from '../../sessions/SessionRegistry.js';
import { ConnectionManager } from '../../server/wsServer.js';
import { Connection } from '../../server/connection.js';
import { RemoteAuthManager } from '../../remote/RemoteAuthManager.js';
import { RemoteManager } from '../../remote/RemoteManager.js';
import { DEFAULT_CONFIG } from '../../config/config.js';
import { SystemMetricsService } from '../SystemMetricsService.js';
import { NullGpuProvider } from '../gpu/NullGpuProvider.js';

class MockWebSocket extends EventEmitter {
  public readyState = 1;
  public sentMessages: string[] = [];

  public send(data: string, cb?: () => void): void {
    this.sentMessages.push(data);
    if (cb) cb();
  }

  public close(): void {
    this.readyState = 3;
    this.emit('close');
  }
}

function createSetup() {
  const manager = new ConnectionManager();
  const registry = new SessionRegistry({
    piExecutablePath: 'node',
    capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 60000,
    connectionManager: manager
  });

  const tmpDev = path.join(os.tmpdir(), `pi_metrics_dev_${Date.now()}_${Math.random()}.json`);
  const auth = new RemoteAuthManager(tmpDev);
  const remoteManager = new RemoteManager(DEFAULT_CONFIG, auth);

  const metricsService = new SystemMetricsService({
    timerProvider: {
      setInterval: () => 1 as any,
      clearInterval: () => {}
    },
    gpuProvider: new NullGpuProvider(),
    sampleCpu: () => ({ percent: 20.0 }),
    sampleMemory: () => ({ usedBytes: 100, totalBytes: 200, percent: 50.0 }),
    sampleDisk: () => ({ usedBytes: 200, totalBytes: 1000, percent: 20.0 })
  });

  const dispatcher = new Dispatcher(registry, manager, undefined, remoteManager, metricsService);

  // Local connection
  const localWs = new MockWebSocket();
  const localConn = new Connection({
    ws: localWs as any,
    expectedToken: 'tok',
    daemonVersion: '0.1.0',
    startedAt: Date.now(),
    piInfo: { path: 'node', version: '0.85.1', supported: true },
    onCommand: async () => {},
    onClose: () => {}
  });
  localConn.state = 'ready';
  localConn.isRemote = false;
  manager.add(localConn);

  // Paired devices
  const pairView = auth.pair(auth.generatePairing(60000).secret, 'View Device', '127.0.0.1', 'view');
  const pairControl = auth.pair(auth.generatePairing(60000).secret, 'Control Device', '127.0.0.1', 'control');

  // Remote connection (view mode)
  const remoteViewWs = new MockWebSocket();
  const remoteViewConn = new Connection({
    ws: remoteViewWs as any,
    expectedToken: 'tok',
    daemonVersion: '0.1.0',
    startedAt: Date.now(),
    piInfo: { path: 'node', version: '0.85.1', supported: true },
    remoteManager,
    onCommand: async () => {},
    onClose: () => {}
  });
  remoteViewConn.state = 'ready';
  remoteViewConn.isRemote = true;
  remoteViewConn.deviceId = pairView.deviceId;
  manager.add(remoteViewConn);

  // Remote connection (control mode)
  const remoteControlWs = new MockWebSocket();
  const remoteControlConn = new Connection({
    ws: remoteControlWs as any,
    expectedToken: 'tok',
    daemonVersion: '0.1.0',
    startedAt: Date.now(),
    piInfo: { path: 'node', version: '0.85.1', supported: true },
    remoteManager,
    onCommand: async () => {},
    onClose: () => {}
  });
  remoteControlConn.state = 'ready';
  remoteControlConn.isRemote = true;
  remoteControlConn.deviceId = pairControl.deviceId;
  manager.add(remoteControlConn);

  const cleanup = () => {
    metricsService.stop();
    try { fs.unlinkSync(tmpDev); } catch {}
  };

  return {
    manager,
    registry,
    metricsService,
    dispatcher,
    localConn,
    localWs,
    remoteViewConn,
    remoteViewWs,
    remoteControlConn,
    remoteControlWs,
    cleanup
  };
}

test('Dispatcher: local connection can subscribe and unsubscribe to system.metrics', async () => {
  const setup = createSetup();
  try {
    // 1. Subscribe
    await setup.dispatcher.handle(setup.localConn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_1',
      ts: Date.now(),
      commandId: 'cid_sub_1',
      sessionId: '@daemon',
      type: 'system.metrics.subscribe',
      payload: {}
    });

    assert.equal(setup.metricsService.getSubscriberCount(), 1);
    const msgs = setup.localWs.sentMessages.map((m) => JSON.parse(m));
    const ack = msgs.find((m) => m.kind === 'ack');
    const res = msgs.find((m) => m.kind === 'result');
    assert.ok(ack, 'Should receive ack');
    assert.ok(res, 'Should receive result');
    assert.equal(res.payload.state, 'completed');
    assert.equal(res.payload.data.intervalMs, 1000);

    // 2. Unsubscribe
    await setup.dispatcher.handle(setup.localConn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_2',
      ts: Date.now(),
      commandId: 'cid_unsub_1',
      sessionId: '@daemon',
      type: 'system.metrics.unsubscribe',
      payload: {}
    });

    assert.equal(setup.metricsService.getSubscriberCount(), 0);
    const msgsAfter = setup.localWs.sentMessages.map((m) => JSON.parse(m));
    const unsubRes = msgsAfter.filter((m) => m.kind === 'result')[1];
    assert.ok(unsubRes);
    assert.equal(unsubRes.payload.state, 'completed');
  } finally {
    setup.cleanup();
  }
});

test('Dispatcher: rejects extra properties in subscribe / unsubscribe payloads', async () => {
  const setup = createSetup();
  try {
    await setup.dispatcher.handle(setup.localConn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_invalid',
      ts: Date.now(),
      commandId: 'cid_invalid_sub',
      sessionId: '@daemon',
      type: 'system.metrics.subscribe',
      payload: { extraProperty: 123 } as any
    });

    const msgs = setup.localWs.sentMessages.map((m) => JSON.parse(m));
    const res = msgs.find((m) => m.kind === 'result');
    assert.equal(res.payload.state, 'rejected');
    const err = msgs.find((m) => m.kind === 'error');
    assert.equal(err.payload.code, 'COMMAND_REJECTED');
  } finally {
    setup.cleanup();
  }
});

test('Dispatcher: remote connections (both view and control) are rejected with REMOTE_FORBIDDEN', async () => {
  const setup = createSetup();
  try {
    // 1. View mode subscribe
    await setup.dispatcher.handle(setup.remoteViewConn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_rem_view',
      ts: Date.now(),
      commandId: 'cid_rem_view',
      sessionId: '@daemon',
      type: 'system.metrics.subscribe',
      payload: {}
    });

    const viewMsgs = setup.remoteViewWs.sentMessages.map((m) => JSON.parse(m));
    const viewRes = viewMsgs.find((m) => m.kind === 'result');
    assert.equal(viewRes.payload.state, 'rejected');
    const viewErr = viewMsgs.find((m) => m.kind === 'error');
    assert.equal(viewErr.payload.code, 'REMOTE_FORBIDDEN');

    // 2. Control mode subscribe
    await setup.dispatcher.handle(setup.remoteControlConn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_rem_ctrl',
      ts: Date.now(),
      commandId: 'cid_rem_ctrl',
      sessionId: '@daemon',
      type: 'system.metrics.subscribe',
      payload: {}
    });

    const ctrlMsgs = setup.remoteControlWs.sentMessages.map((m) => JSON.parse(m));
    const ctrlRes = ctrlMsgs.find((m) => m.kind === 'result');
    assert.equal(ctrlRes.payload.state, 'rejected');
    const ctrlErr = ctrlMsgs.find((m) => m.kind === 'error');
    assert.equal(ctrlErr.payload.code, 'REMOTE_FORBIDDEN');
    assert.equal(setup.metricsService.getSubscriberCount(), 0);
  } finally {
    setup.cleanup();
  }
});

test('Dispatcher: connection manager close hook unsubscribes closed connection', async () => {
  const setup = createSetup();
  try {
    await setup.dispatcher.handle(setup.localConn, {
      protocol: 1,
      kind: 'command',
      id: 'cmd_close_test',
      ts: Date.now(),
      commandId: 'cid_close_test',
      sessionId: '@daemon',
      type: 'system.metrics.subscribe',
      payload: {}
    });

    assert.equal(setup.metricsService.getSubscriberCount(), 1);

    // Remove connection from ConnectionManager (simulates connection close)
    setup.manager.remove(setup.localConn);
    assert.equal(setup.metricsService.getSubscriberCount(), 0);
  } finally {
    setup.cleanup();
  }
});
