import test from 'node:test';
import * as assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { Dispatcher } from '../Dispatcher.js';
import { SessionRegistry } from '../../sessions/SessionRegistry.js';
import { ConnectionManager } from '../../server/wsServer.js';
import { Connection } from '../../server/connection.js';

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

function createTestSetup() {
  const manager = new ConnectionManager();
  const registry = new SessionRegistry({
    piExecutablePath: 'node',
    capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 60000,
    connectionManager: manager
  });
  const dispatcher = new Dispatcher(registry, manager);

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
