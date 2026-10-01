import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as http from 'node:http';
import { createHttpServer } from '../httpServer.js';
import { DEFAULT_CONFIG } from '../../config/config.js';
import { ConnectionManager } from '../wsServer.js';

function request(port: number, headers: Record<string, string> = {}): Promise<{ status: number; body: any }> {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port, path: '/api/session-bootstrap', headers }, (res) => {
      let text = '';
      res.on('data', (chunk) => { text += chunk; });
      res.on('end', () => resolve({ status: res.statusCode!, body: JSON.parse(text) }));
    }).on('error', reject);
  });
}

test('HTTP bootstrap rejects hostile Host and Origin, permits daemon same-origin', async () => {
  const server = createHttpServer({ config: DEFAULT_CONFIG, token: 'secret', version: 'test', startedAt: Date.now() });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = (server.address() as any).port;
  try {
    assert.equal((await request(port, { Host: `attacker.example:${port}` })).status, 403);
    assert.equal((await request(port, { Origin: 'https://attacker.example' })).status, 403);
    const trusted = await request(port, { Origin: `http://127.0.0.1:${port}` });
    assert.equal(trusted.status, 200);
    assert.equal(trusted.body.token, 'secret');
  } finally { await new Promise<void>((resolve) => server.close(() => resolve())); }
});

test('application broadcasts do not leak to clients before authentication', () => {
  const manager = new ConnectionManager();
  const received: any[] = [];
  const untrusted = { id: 'untrusted', state: 'authenticating', attachedSessions: new Set(), send: () => received.push('untrusted') };
  const trusted = { id: 'trusted', state: 'ready', attachedSessions: new Set(), send: () => received.push('trusted') };
  manager.add(untrusted as any);
  manager.add(trusted as any);
  const event = { protocol: 1, kind: 'event', sessionId: '@daemon', type: 'session.indexChanged' } as any;
  manager.broadcast('@daemon', event);
  manager.broadcastAll(event);
  assert.deepEqual(received, ['trusted', 'trusted']);
});
