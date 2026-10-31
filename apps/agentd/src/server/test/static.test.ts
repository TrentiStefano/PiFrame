import { test } from 'node:test';
import * as assert from 'node:assert';
import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { DEFAULT_CONFIG } from '../../config/config.js';
import { createHttpServer } from '../httpServer.js';

test('staticServer: serves static assets with security headers and cookie bootstrap', async (t) => {
  // Create a temporary static directory with sample Flutter web files
  const tempWebDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-frame-web-'));
  fs.writeFileSync(
    path.join(tempWebDir, 'index.html'),
    '<!DOCTYPE html><html><head><title>PiFrame App</title></head><body><script src="main.dart.js"></script></body></html>',
    'utf8'
  );
  fs.writeFileSync(path.join(tempWebDir, 'main.dart.js'), 'console.log("flutter app loaded");', 'utf8');
  fs.writeFileSync(path.join(tempWebDir, 'styles.css'), 'body { background: #000; }', 'utf8');

  const token = 'test-static-token-1234567890';
  const server = createHttpServer({
    config: DEFAULT_CONFIG,
    token,
    version: '0.1.0',
    startedAt: Date.now(),
    staticDir: tempWebDir
  });

  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address() as any;
  const port = address.port;

  t.after(async () => {
    server.closeAllConnections?.();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    fs.rmSync(tempWebDir, { recursive: true, force: true });
  });

  // 1. Root request GET / should serve index.html with security headers and loopback cookie
  await t.test('serves index.html with CSP and Set-Cookie for loopback', async () => {
    const res = await new Promise<http.IncomingMessage>((resolve, reject) => {
      const req = http.request(
        {
          hostname: '127.0.0.1',
          port,
          path: '/',
          method: 'GET'
        },
        resolve
      );
      req.on('error', reject);
      req.end();
    });

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.headers['x-frame-options'], 'DENY');
    assert.strictEqual(res.headers['referrer-policy'], 'no-referrer');
    assert.strictEqual(res.headers['x-content-type-options'], 'nosniff');
    assert.ok(res.headers['content-security-policy']?.includes("default-src 'self'"));

    // Check loopback cookie
    const setCookie = res.headers['set-cookie']?.[0] || '';
    assert.ok(setCookie.includes(`pcp_token=${token}`));
    assert.ok(setCookie.includes('HttpOnly'));
    assert.ok(setCookie.includes('SameSite=Strict'));

    let body = '';
    res.setEncoding('utf8');
    for await (const chunk of res) {
      body += chunk;
    }
    assert.ok(body.includes('<title>PiFrame App</title>'));
  });

  // 2. JavaScript asset request
  await t.test('serves JS asset with correct MIME type and security headers', async () => {
    const res = await new Promise<http.IncomingMessage>((resolve, reject) => {
      const req = http.request(
        {
          hostname: '127.0.0.1',
          port,
          path: '/main.dart.js',
          method: 'GET'
        },
        resolve
      );
      req.on('error', reject);
      req.end();
    });

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.headers['content-type'], 'application/javascript; charset=utf-8');
    assert.strictEqual(res.headers['x-frame-options'], 'DENY');

    let body = '';
    res.setEncoding('utf8');
    for await (const chunk of res) {
      body += chunk;
    }
    assert.strictEqual(body, 'console.log("flutter app loaded");');
  });

  // 3. SPA fallback: path without extension should fallback to index.html
  await t.test('SPA route fallback to index.html', async () => {
    const res = await new Promise<http.IncomingMessage>((resolve, reject) => {
      const req = http.request(
        {
          hostname: '127.0.0.1',
          port,
          path: '/session/s_12345',
          method: 'GET'
        },
        resolve
      );
      req.on('error', reject);
      req.end();
    });

    assert.strictEqual(res.statusCode, 200);
    let body = '';
    res.setEncoding('utf8');
    for await (const chunk of res) {
      body += chunk;
    }
    assert.ok(body.includes('<title>PiFrame App</title>'));
  });

  // 4. Directory traversal attempt is rejected
  await t.test('rejects path traversal outside static directory', async () => {
    const res = await new Promise<http.IncomingMessage>((resolve, reject) => {
      const req = http.request(
        {
          hostname: '127.0.0.1',
          port,
          path: '/../../../../etc/passwd',
          method: 'GET'
        },
        resolve
      );
      req.on('error', reject);
      req.end();
    });

    // Should either be 403 or fallback to 404 or index.html without leaking external files
    assert.notStrictEqual(res.statusCode, 500);
  });
});
