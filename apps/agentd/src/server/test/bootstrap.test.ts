import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as http from 'node:http';
import { EventEmitter } from 'node:events';
import type { PcpEnvelope } from '@piframe/pcp-ts';
import { createHttpServer } from '../httpServer.js';
import { DEFAULT_CONFIG } from '../../config/config.js';
import { ConnectionManager } from '../wsServer.js';
import { Connection, type ConnectionSocket, type ConnectionOptions } from '../connection.js';

type BootstrapResponse = { status: number; body: Record<string, unknown> };

function request(port: number, headers: Record<string, string> = {}): Promise<BootstrapResponse> {
  return new Promise((resolve, reject) => {
    http
      .get({ host: '127.0.0.1', port, path: '/api/session-bootstrap', headers }, (res) => {
        let text = '';
        res.on('data', (chunk) => {
          text += chunk;
        });
        res.on('end', () => resolve({ status: res.statusCode!, body: JSON.parse(text) }));
      })
      .on('error', reject);
  });
}

function listeningPort(server: { address(): { port: number } | string | null }): number {
  const address = server.address();
  if (address === null || typeof address === 'string') throw new Error('server is not listening on a TCP port');
  return address.port;
}

/** A socket that records every frame the connection writes. */
class RecordingSocket extends EventEmitter implements ConnectionSocket {
  public readyState = 1;
  public sent: string[] = [];

  public send(data: string, cb: () => void): void {
    this.sent.push(data);
    cb();
  }

  public close(): void {
    this.readyState = 3;
  }
}

function connectionOptions(ws: ConnectionSocket): ConnectionOptions {
  return {
    ws,
    expectedToken: 'secret',
    daemonVersion: 'test',
    startedAt: Date.now(),
    piInfo: { path: 'pi', version: '0.85.1', supported: true },
    onCommand: async () => {},
    onClose: () => {}
  };
}

test('HTTP bootstrap rejects hostile Host and Origin, permits daemon same-origin', async () => {
  const server = createHttpServer({ config: DEFAULT_CONFIG, token: 'secret', version: 'test', startedAt: Date.now() });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = listeningPort(server);
  try {
    assert.equal((await request(port, { Host: `attacker.example:${port}` })).status, 403);
    assert.equal((await request(port, { Origin: 'https://attacker.example' })).status, 403);
    const trusted = await request(port, { Origin: `http://127.0.0.1:${port}` });
    assert.equal(trusted.status, 200);
    assert.equal(trusted.body.token, 'secret');
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

test('application broadcasts do not leak to clients before authentication', () => {
  const manager = new ConnectionManager();
  const untrustedSocket = new RecordingSocket();
  const trustedSocket = new RecordingSocket();
  const untrusted = new Connection(connectionOptions(untrustedSocket));
  const trusted = new Connection(connectionOptions(trustedSocket));
  trusted.state = 'ready';
  manager.add(untrusted);
  manager.add(trusted);
  const event: PcpEnvelope = {
    protocol: 1,
    kind: 'event',
    id: 'evt_bootstrap',
    ts: 0,
    sessionId: '@daemon',
    type: 'session.indexChanged',
    payload: {}
  };
  manager.broadcast('@daemon', event);
  manager.broadcastAll(event);
  assert.equal(untrustedSocket.sent.length, 0);
  assert.equal(trustedSocket.sent.length, 2);
  untrusted.close(1000, 'test done');
  trusted.close(1000, 'test done');
});
