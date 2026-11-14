import test from 'node:test';
import * as assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { Connection } from '../connection.js';

class MockWebSocket extends EventEmitter {
  public readyState = 1; // WebSocket.OPEN
  public sentMessages: string[] = [];
  public closedCode?: number;
  public closedReason?: string;

  public send(data: string, cb?: () => void): void {
    this.sentMessages.push(data);
    if (cb) cb();
  }

  public close(code: number, reason: string): void {
    this.readyState = 3; // CLOSED
    this.closedCode = code;
    this.closedReason = reason;
    this.emit('close');
  }
}

test('Connection: closes with 4003 if token is invalid', () => {
  const ws = new MockWebSocket();
  let closed = false;

  const conn = new Connection({
    ws: ws as any,
    expectedToken: 'secret_valid_token',
    daemonVersion: '0.1.0',
    startedAt: Date.now(),
    piInfo: { path: 'pi', version: '0.85.1', supported: true },
    onCommand: async () => {},
    onClose: () => { closed = true; }
  });

  // Client sends hello with wrong token
  ws.emit(
    'message',
    Buffer.from(
      JSON.stringify({
        protocol: 1,
        kind: 'hello',
        id: 'h_1',
        ts: Date.now(),
        type: 'connection.hello',
        payload: {
          token: 'WRONG_TOKEN',
          client: {
            name: 'test-gui',
            version: '1.0.0',
            platform: 'desktop'
          },
          encoding: 'json',
          capabilities: ['replay.v1']
        }
      })
    )
  );

  assert.equal(ws.closedCode, 4003);
  assert.equal(closed, true);
});

test('Connection: authenticates successfully and sends welcome frame', () => {
  const ws = new MockWebSocket();
  const token = 'correct_token_12345';

  const conn = new Connection({
    ws: ws as any,
    expectedToken: token,
    daemonVersion: '0.1.0',
    startedAt: Date.now(),
    piInfo: { path: 'pi', version: '0.85.1', supported: true },
    onCommand: async () => {},
    onClose: () => {}
  });

  ws.emit(
    'message',
    Buffer.from(
      JSON.stringify({
        protocol: 1,
        kind: 'hello',
        id: 'h_2',
        ts: Date.now(),
        type: 'connection.hello',
        payload: {
          token,
          client: {
            name: 'test-gui',
            version: '1.0.0',
            platform: 'desktop'
          },
          encoding: 'json',
          capabilities: ['replay.v1']
        }
      })
    )
  );

  assert.equal(conn.state, 'ready');
  assert.ok(ws.sentMessages.length >= 1);
  const welcome = JSON.parse(ws.sentMessages[0]);
  assert.equal(welcome.kind, 'welcome');
  assert.equal(welcome.payload.daemon.version, '0.1.0');
  assert.equal(welcome.payload.pi.version, '0.85.1');

  conn.close(1000, 'Normal');
});

function frame(value: Record<string, unknown>): Buffer {
  return Buffer.from(JSON.stringify({ protocol: 1, ts: Date.now(), ...value }));
}

function readyConnection() {
  const ws = new MockWebSocket();
  const conn = new Connection({
    ws: ws as any, expectedToken: 'tok', daemonVersion: '0.1.0', startedAt: Date.now(),
    piInfo: { path: 'pi', version: '0.85.1', supported: true }, onCommand: async () => {}, onClose: () => {},
  });
  return { ws, conn };
}

const hello = frame({
  kind: 'hello', id: 'h', type: 'connection.hello',
  payload: { token: 'tok', client: { name: 't', version: '1', platform: 'desktop' }, encoding: 'json', capabilities: [] },
});

// Timers are mocked, setImmediate is real: it models the socket reads that run after a late timer.
const nextTurn = () => new Promise((resolve) => setImmediate(resolve));

test('Connection: a pong read right after a late heartbeat timer keeps the connection open', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
  const { ws, conn } = readyConnection();
  ws.emit('message', hello);
  t.mock.timers.tick(15000); // ping sent
  t.mock.timers.tick(10000); // pong timer fires while the pong is still unread (event loop was blocked)
  ws.emit('message', frame({ kind: 'pong', id: 'p', type: 'heartbeat.pong', payload: {} }));
  await nextTurn();
  assert.equal(ws.closedCode, undefined);
  assert.equal(conn.state, 'ready');
  conn.close(1000, 'Normal');
});

test('Connection: still closes with 4008 when no pong ever arrives', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
  const { ws } = readyConnection();
  ws.emit('message', hello);
  t.mock.timers.tick(15000);
  t.mock.timers.tick(10000);
  await nextTurn();
  assert.equal(ws.closedCode, 4008);
});

test('Connection: a hello read right after a late handshake timer is accepted', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
  const { ws, conn } = readyConnection();
  t.mock.timers.tick(5000); // handshake timer fires while the hello is still unread
  ws.emit('message', hello);
  await nextTurn();
  assert.equal(ws.closedCode, undefined);
  assert.equal(conn.state, 'ready');
  conn.close(1000, 'Normal');
});
