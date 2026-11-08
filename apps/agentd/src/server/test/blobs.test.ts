import { test } from 'node:test';
import * as assert from 'node:assert';
import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { DEFAULT_CONFIG } from '../../config/config.js';
import { createHttpServer } from '../httpServer.js';
import { safeBlobName, pruneOldBlobs, getBlobsDir } from '../blobs.js';

test('safeBlobName never yields a path and keeps/derives an extension', () => {
  assert.strictEqual(safeBlobName(encodeURIComponent('IMG 7660.png'), 'image/png'), 'IMG 7660.png');
  assert.strictEqual(safeBlobName(encodeURIComponent('../../etc/passwd'), undefined), 'passwd');
  assert.strictEqual(safeBlobName(encodeURIComponent('C:\\Users\\me\\shot'), 'image/jpeg'), 'shot.jpg');
  assert.strictEqual(safeBlobName(undefined, 'image/png'), 'file.png');
  assert.ok(!safeBlobName('..%2F..%2Fx.png', undefined).includes('/'));
});

test('blob upload over the authenticated listener stores the file and serves it back', async (t) => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'pf-blobs-'));
  const prev = process.env.PI_FRAME_HOME;
  process.env.PI_FRAME_HOME = home;
  const token = 'test-blob-token-1234567890';
  const server = createHttpServer({ config: DEFAULT_CONFIG, token, version: '0', startedAt: Date.now() });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = (server.address() as any).port;
  t.after(async () => {
    server.closeAllConnections?.();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    if (prev === undefined) delete process.env.PI_FRAME_HOME;
    else process.env.PI_FRAME_HOME = prev;
    fs.rmSync(home, { recursive: true, force: true });
  });

  const request = (method: string, p: string, headers: Record<string, string>, body?: Buffer) =>
    new Promise<{ res: http.IncomingMessage; body: Buffer }>((resolve, reject) => {
      const req = http.request({ hostname: '127.0.0.1', port, path: p, method, headers }, (res) => {
        const chunks: Buffer[] = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve({ res, body: Buffer.concat(chunks) }));
      });
      req.on('error', reject);
      req.end(body);
    });

  const png = Buffer.from('89504e470d0a1a0a0000', 'hex');
  const auth = { Authorization: 'Bearer ' + token };

  const unauth = await request('POST', '/api/blobs', { 'Content-Type': 'image/png' }, png);
  assert.strictEqual(unauth.res.statusCode, 401);

  const up = await request(
    'POST',
    '/api/blobs',
    { ...auth, 'Content-Type': 'image/png', 'X-File-Name': encodeURIComponent('IMG 7660.png') },
    png
  );
  assert.strictEqual(up.res.statusCode, 201);
  const info = JSON.parse(up.body.toString());
  assert.match(info.blobId, /^blob_[a-f0-9]{32}$/);
  assert.strictEqual(info.name, 'IMG 7660.png');
  assert.ok(path.isAbsolute(info.path));
  assert.ok(info.path.startsWith(getBlobsDir()));
  assert.deepStrictEqual(fs.readFileSync(info.path), png);

  const down = await request('GET', '/api/blobs/' + info.blobId, auth);
  assert.strictEqual(down.res.statusCode, 200);
  assert.strictEqual(down.res.headers['content-type'], 'image/png');
  assert.deepStrictEqual(down.body, png);

  const traversal = await request('GET', '/api/blobs/..%2F..%2Fconfig.json', auth);
  assert.strictEqual(traversal.res.statusCode, 404);

  // Old uploads are pruned.
  const dir = path.join(getBlobsDir(), info.blobId);
  const old = new Date(Date.now() - 20 * 24 * 3600 * 1000);
  fs.utimesSync(dir, old, old);
  pruneOldBlobs();
  assert.ok(!fs.existsSync(dir));
});
