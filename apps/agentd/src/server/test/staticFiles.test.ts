import { test } from 'node:test';
import * as assert from 'node:assert';
import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import * as zlib from 'node:zlib';
import { DEFAULT_CONFIG } from '../../config/config.js';
import { createHttpServer } from '../httpServer.js';
import { stripServiceWorkerSettings } from '../staticFiles.js';
import { newestWebDir } from '../static.js';

function get(port: number, p: string, headers: Record<string, string> = {}) {
  return new Promise<{ res: http.IncomingMessage; body: Buffer }>((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port, path: p, method: 'GET', headers }, (res) => {
      const chunks: Buffer[] = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({ res, body: Buffer.concat(chunks) }));
    });
    req.on('error', reject);
    req.end();
  });
}

test('stripServiceWorkerSettings removes the Flutter service worker registration', () => {
  const src = '_flutter.loader.load({\n  serviceWorkerSettings: {\n    serviceWorkerVersion: "1" /* x */\n  }\n});';
  const out = stripServiceWorkerSettings(src);
  assert.ok(!out.includes('serviceWorker'));
  assert.ok(out.includes('_flutter.loader.load('));
});

test('newestWebDir prefers the most recently built web bundle over a stale one', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-frame-newest-'));
  const stale = path.join(root, 'stale');
  const fresh = path.join(root, 'fresh');
  for (const d of [stale, fresh]) {
    fs.mkdirSync(d);
    fs.writeFileSync(path.join(d, 'index.html'), '<html></html>');
    fs.writeFileSync(path.join(d, 'main.dart.js'), '//');
  }
  fs.utimesSync(path.join(stale, 'main.dart.js'), new Date('2026-01-01'), new Date('2026-01-01'));
  assert.strictEqual(newestWebDir([stale, fresh]), fresh);
  assert.strictEqual(newestWebDir([fresh, stale]), fresh);
  fs.rmSync(root, { recursive: true, force: true });
});

test('static files: revalidation, compression and service worker neutralisation', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-frame-web-'));
  const bigJs = 'console.log("x");\n'.repeat(5000);
  fs.writeFileSync(path.join(dir, 'index.html'), '<html></html>');
  fs.writeFileSync(path.join(dir, 'main.dart.js'), bigJs);
  fs.writeFileSync(path.join(dir, 'flutter_service_worker.js'), '// old caching worker');
  fs.writeFileSync(
    path.join(dir, 'flutter_bootstrap.js'),
    '_flutter.loader.load({ serviceWorkerSettings: { serviceWorkerVersion: "9" } });'
  );

  const server = createHttpServer({
    config: DEFAULT_CONFIG,
    token: 'tok',
    version: '0.0.0',
    startedAt: Date.now(),
    staticDir: dir
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = (server.address() as any).port;
  t.after(async () => {
    server.closeAllConnections?.();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    fs.rmSync(dir, { recursive: true, force: true });
  });

  await t.test('sends ETag + no-cache and answers 304 to a matching If-None-Match', async () => {
    const first = await get(port, '/main.dart.js');
    assert.strictEqual(first.res.statusCode, 200);
    assert.strictEqual(first.res.headers['cache-control'], 'no-cache');
    const etag = first.res.headers['etag'] as string;
    assert.ok(etag);
    const second = await get(port, '/main.dart.js', { 'If-None-Match': etag });
    assert.strictEqual(second.res.statusCode, 304);
    assert.strictEqual(second.body.length, 0);
  });

  await t.test('compresses with brotli / gzip when accepted and stays identity otherwise', async () => {
    const br = await get(port, '/main.dart.js', { 'Accept-Encoding': 'br, gzip' });
    assert.strictEqual(br.res.headers['content-encoding'], 'br');
    assert.strictEqual(zlib.brotliDecompressSync(br.body).toString(), bigJs);
    assert.ok(br.body.length < bigJs.length / 10);

    const gz = await get(port, '/main.dart.js', { 'Accept-Encoding': 'gzip' });
    assert.strictEqual(gz.res.headers['content-encoding'], 'gzip');
    assert.strictEqual(zlib.gunzipSync(gz.body).toString(), bigJs);

    const plain = await get(port, '/main.dart.js');
    assert.strictEqual(plain.res.headers['content-encoding'], undefined);
    assert.strictEqual(plain.body.toString(), bigJs);
  });

  await t.test('replaces the Flutter service worker and strips its registration', async () => {
    const sw = await get(port, '/flutter_service_worker.js');
    assert.ok(sw.body.toString().includes('unregister'));
    const boot = await get(port, '/flutter_bootstrap.js');
    assert.ok(!boot.body.toString().includes('serviceWorker'));
  });
});
