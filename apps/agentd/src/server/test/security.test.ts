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

    const clients: WebSocket[] = [];

    try {
      // 3a. Disallowed Origin: resolve when connection is rejected.
      // The server writes 403 then destroys the socket, so under load Windows
      // may deliver RST before the client parses the status.
      await new Promise<void>((resolve, reject) => {
        let settled = false;
        const settleResolve = () => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve();
        };
        const settleReject = (err: Error) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          reject(err);
        };

        const timer = setTimeout(() => {
          settleReject(new Error('Timed out waiting for origin rejection'));
        }, 5000);

        const ws = new WebSocket(`ws://127.0.0.1:${port}`, {
          headers: {
            Origin: 'http://malicious-website.com'
          }
        });
        clients.push(ws);

        ws.on('unexpected-response', (_req, res) => {
          if (res.statusCode === 403) {
            settleResolve();
          } else {
            settleReject(new Error(`Expected 403 Forbidden, received status ${res.statusCode}`));
          }
        });

        ws.on('open', () => {
          ws.close();
          settleReject(new Error('Connection should not have opened for disallowed origin'));
        });

        ws.on('error', (err: any) => {
          const msg = err?.message || '';
          const code = err?.code || '';
          if (
            msg.includes('403') ||
            msg.includes('Unexpected server response') ||
            code === 'ECONNRESET' ||
            code === 'EPIPE' ||
            msg.includes('socket hang up')
          ) {
            settleResolve();
            return;
          }
          settleReject(err instanceof Error ? err : new Error(String(err)));
        });
      });

      // 3b. Invalid token in hello frame is closed with 4003 (proves server is still alive and enforcing auth)
      await new Promise<void>((resolve, reject) => {
        let settled = false;
        const settleResolve = () => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve();
        };
        const settleReject = (err: Error) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          reject(err);
        };

        const timer = setTimeout(() => {
          settleReject(new Error('Timed out waiting for 4003 close on invalid token'));
        }, 5000);

        const ws = new WebSocket(`ws://127.0.0.1:${port}`);
        clients.push(ws);

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
          if (code === 4003) {
            settleResolve();
          } else {
            settleReject(new Error(`Expected close code 4003 on invalid token, got ${code}`));
          }
        });

        ws.on('error', (err: any) => {
          settleReject(err instanceof Error ? err : new Error(String(err)));
        });
      });
    } finally {
      for (const client of clients) {
        try {
          client.terminate();
        } catch {}
      }
      wss.close();
      await new Promise<void>((resolve) => httpServer.close(() => resolve()));
    }
  });
});
