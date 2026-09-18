import { test } from 'node:test';
import * as assert from 'node:assert';
import * as http from 'node:http';
import WebSocket from 'ws';
import { timingSafeEqualStrings } from '../auth.js';
import { isOriginAllowed } from '../origin.js';
import { createHttpServer } from '../httpServer.js';
import { createWsServer } from '../wsServer.js';
import { DEFAULT_CONFIG } from '../../config/config.js';

test('Security Review Suite: constant-time comparison, origin validation, token enforcement', async (t) => {
  // 1. Test timingSafeEqualStrings
  await t.test('timingSafeEqualStrings correctly validates matching and non-matching tokens', () => {
    const tokenA = 'f7c8b2a19e0d4c3b5a6f8e7d9c0b1a2f';
    const tokenB = 'f7c8b2a19e0d4c3b5a6f8e7d9c0b1a2f';
    const tokenC = 'f7c8b2a19e0d4c3b5a6f8e7d9c0b1a2e'; // 1 char diff
    const tokenShort = 'short';

    assert.strictEqual(timingSafeEqualStrings(tokenA, tokenB), true);
    assert.strictEqual(timingSafeEqualStrings(tokenA, tokenC), false);
    assert.strictEqual(timingSafeEqualStrings(tokenA, tokenShort), false);
  });

  // 2. Test isOriginAllowed
  await t.test('isOriginAllowed permits loopback and blocks untrusted web origins', () => {
    const daemonPort = 8080;
    const allowed = ['http://localhost:8080', 'http://127.0.0.1:8080'];

    // Local desktop / CLI (no Origin header) -> allowed
    assert.strictEqual(isOriginAllowed(undefined, allowed, daemonPort), true);

    // Loopback origin on correct port -> allowed
    assert.strictEqual(isOriginAllowed('http://127.0.0.1:8080', allowed, daemonPort), true);
    assert.strictEqual(isOriginAllowed('http://localhost:8080', allowed, daemonPort), true);

    // Disallowed external origin -> rejected
    assert.strictEqual(isOriginAllowed('http://malicious-site.com', allowed, daemonPort), false);
    assert.strictEqual(isOriginAllowed('https://evil.org:8080', allowed, daemonPort), false);
  });

  // 3. Integration test against running server: Origin rejection & Token enforcement
  await t.test('WS server rejects unauthorized origins and missing tokens', async () => {
    const token = 'test-security-token-999999999';
    const version = '0.1.0';
    const startedAt = Date.now();

    const httpServer = createHttpServer({
      config: DEFAULT_CONFIG,
      token,
      version,
      startedAt
    });

    await new Promise<void>((resolve, reject) => {
      httpServer.listen(0, '127.0.0.1', () => resolve());
      httpServer.on('error', reject);
    });

    const port = (httpServer.address() as any).port;

    const { wss } = createWsServer({
      httpServer,
      config: DEFAULT_CONFIG,
      token,
      version,
      startedAt,
      piInfo: { path: 'pi', version: '0.85.0', supported: true },
      port,
      onCommand: async () => {},
      onAttach: async () => {},
      onDetach: async () => {}
    });

    try {
      // 3a. Disallowed Origin should be rejected with 403 on HTTP upgrade
      await new Promise<void>((resolve, reject) => {
        const ws = new WebSocket(`ws://127.0.0.1:${port}`, {
          headers: {
            Origin: 'http://malicious-website.com'
          }
        });

        ws.on('open', () => {
          ws.close();
          reject(new Error('Connection should not have opened for disallowed origin'));
        });

        ws.on('error', (err: any) => {
          // Expected rejection
          assert.ok(err.message.includes('403') || err.message.includes('Unexpected server response'));
          resolve();
        });
      });

      // 3b. Missing token in hello frame is closed with 4003
      await new Promise<void>((resolve) => {
        const ws = new WebSocket(`ws://127.0.0.1:${port}`);
        ws.on('open', () => {
          ws.send(
            JSON.stringify({
              protocol: 1,
              kind: 'hello',
              id: 'hl_test',
              ts: Date.now(),
              type: 'connection.hello',
              payload: {
                token: 'wrong-token',
                client: { name: 'attacker', version: '1.0', platform: 'web' },
                encoding: 'json'
              }
            })
          );
        });

        ws.on('close', (code) => {
          assert.strictEqual(code, 4003, 'Should close with 4003 on invalid token');
          resolve();
        });
      });
    } finally {
      wss.close();
      await new Promise<void>((resolve) => httpServer.close(() => resolve()));
    }
  });
});
