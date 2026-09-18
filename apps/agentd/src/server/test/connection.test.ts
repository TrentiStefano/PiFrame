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
