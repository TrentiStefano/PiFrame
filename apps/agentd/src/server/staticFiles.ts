import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as zlib from 'node:zlib';
import * as crypto from 'node:crypto';

/**
 * Efficient static file delivery for the Flutter web build, tuned for phones behind a tunnel:
 *  - ETag + `no-cache` revalidation (a new build is picked up immediately, repeat loads are 304s)
 *  - Brotli/gzip compression cached in memory (main.dart.js ~4MB, canvaskit wasm ~7MB)
 *  - Flutter's own service worker is neutralised: its cache-first strategy served a stale app shell
 *    after PiFrame/daemon updates, which surfaced as an empty page on the phone.
 */

const COMPRESSIBLE = new Set([
  '.html', '.js', '.mjs', '.css', '.json', '.wasm', '.svg', '.map', '.ttf', '.otf', '.bin', '.symbols', ''
]);
const MAX_CACHED_FILE_BYTES = 24 * 1024 * 1024;
const MAX_CACHE_TOTAL_BYTES = 160 * 1024 * 1024;

interface CachedAsset {
  key: string;
  etag: string;
  raw: Buffer;
  br?: Promise<Buffer>;
  gzip?: Promise<Buffer>;
}

const assetCache = new Map<string, CachedAsset>();
let assetCacheBytes = 0;

/** Replaces any previously installed Flutter service worker with one that removes itself. */
export const SELF_DESTRUCT_SERVICE_WORKER = `// PiFrame: the web app does not use a service worker. This script removes legacy ones.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
    } catch (e) {}
    try { await self.registration.unregister(); } catch (e) {}
    try {
      const clients = await self.clients.matchAll({ type: 'window' });
      clients.forEach((c) => { try { c.navigate(c.url); } catch (e) {} });
    } catch (e) {}
  })());
});
self.addEventListener('fetch', () => {});
`;

/** Removes the service worker registration from the generated flutter_bootstrap.js. */
export function stripServiceWorkerSettings(source: string): string {
  return source.replace(/serviceWorkerSettings\s*:\s*\{[\s\S]*?\}\s*,?/, '');
}

function weakEtag(buf: Buffer | { size: number; mtimeMs: number }): string {
  if (Buffer.isBuffer(buf)) {
    return `"${crypto.createHash('sha1').update(buf).digest('base64url').slice(0, 22)}"`;
  }
  return `W/"${buf.size.toString(16)}-${Math.floor(buf.mtimeMs).toString(16)}"`;
}

function loadAsset(filePath: string, stat: fs.Stats, transform?: (s: string) => string): CachedAsset {
  const key = `${filePath}|${stat.size}|${Math.floor(stat.mtimeMs)}`;
  const hit = assetCache.get(key);
  if (hit) return hit;

  let raw = fs.readFileSync(filePath);
  if (transform) raw = Buffer.from(transform(raw.toString('utf8')), 'utf8');
  const asset: CachedAsset = { key, etag: weakEtag(raw), raw };

  // Drop superseded versions of the same file, then enforce the global budget.
  const prefix = `${filePath}|`;
  for (const [k, v] of assetCache) {
    if (k.startsWith(prefix)) {
      assetCacheBytes -= v.raw.length;
      assetCache.delete(k);
    }
  }
  if (assetCacheBytes + raw.length > MAX_CACHE_TOTAL_BYTES) {
    assetCache.clear();
    assetCacheBytes = 0;
  }
  assetCache.set(key, asset);
  assetCacheBytes += raw.length;
  return asset;
}

function brotli(asset: CachedAsset): Promise<Buffer> {
  asset.br ??= new Promise<Buffer>((resolve, reject) =>
    zlib.brotliCompress(
      asset.raw,
      {
        params: {
          [zlib.constants.BROTLI_PARAM_QUALITY]: 6,
          [zlib.constants.BROTLI_PARAM_SIZE_HINT]: asset.raw.length
        }
      },
      (err, out) => (err ? reject(err) : resolve(out))
    )
  );
  return asset.br;
}

function gzip(asset: CachedAsset): Promise<Buffer> {
  asset.gzip ??= new Promise<Buffer>((resolve, reject) =>
    zlib.gzip(asset.raw, { level: 6 }, (err, out) => (err ? reject(err) : resolve(out)))
  );
  return asset.gzip;
}

function etagMatches(header: string | string[] | undefined, etag: string): boolean {
  if (!header) return false;
  const value = Array.isArray(header) ? header.join(',') : header;
  if (value.trim() === '*') return true;
  const strip = (t: string) => t.trim().replace(/^W\//, '');
  const target = strip(etag);
  return value.split(',').some((t) => strip(t) === target);
}

export interface ServeFileOptions {
  filePath: string;
  contentType: string;
}

/** Special files that need content rewriting or replacement. */
function specialContent(filePath: string): { transform?: (s: string) => string; fixed?: string } {
  const base = path.basename(filePath);
  if (base === 'flutter_bootstrap.js') return { transform: stripServiceWorkerSettings };
  if (base === 'flutter_service_worker.js') return { fixed: SELF_DESTRUCT_SERVICE_WORKER };
  return {};
}

export async function sendStaticFile(
  req: http.IncomingMessage,
  res: http.ServerResponse,
  opts: ServeFileOptions
): Promise<void> {
  const { filePath, contentType } = opts;
  const stat = fs.statSync(filePath);
  const ext = path.extname(filePath).toLowerCase();
  const special = specialContent(filePath);
  const isHead = req.method === 'HEAD';

  const baseHeaders: Record<string, string | number> = {
    'Content-Type': contentType,
    // Always revalidate: build artifacts are not content-hashed, so a stale copy would mix versions.
    'Cache-Control': 'no-cache',
    Vary: 'Accept-Encoding'
  };

  const cacheable = Boolean(special.transform || special.fixed) ||
    (COMPRESSIBLE.has(ext) && stat.size <= MAX_CACHED_FILE_BYTES);

  if (!cacheable) {
    // Large/binary media: stream straight from disk (already compressed formats).
    const etag = weakEtag(stat);
    baseHeaders.ETag = etag;
    if (etagMatches(req.headers['if-none-match'], etag)) {
      res.writeHead(304, baseHeaders);
      res.end();
      return;
    }
    res.writeHead(200, { ...baseHeaders, 'Content-Length': stat.size });
    if (isHead) res.end();
    else fs.createReadStream(filePath).pipe(res);
    return;
  }

  let asset: CachedAsset;
  if (special.fixed !== undefined) {
    const raw = Buffer.from(special.fixed, 'utf8');
    asset = { key: 'fixed', etag: weakEtag(raw), raw };
  } else {
    asset = loadAsset(filePath, stat, special.transform);
  }
  baseHeaders.ETag = asset.etag;

  if (etagMatches(req.headers['if-none-match'], asset.etag)) {
    res.writeHead(304, baseHeaders);
    res.end();
    return;
  }

  let body = asset.raw;
  const acceptEncoding = String(req.headers['accept-encoding'] ?? '');
  if (COMPRESSIBLE.has(ext) && asset.raw.length > 512) {
    try {
      if (/\bbr\b/.test(acceptEncoding)) {
        body = await brotli(asset);
        baseHeaders['Content-Encoding'] = 'br';
      } else if (/\bgzip\b/.test(acceptEncoding)) {
        body = await gzip(asset);
        baseHeaders['Content-Encoding'] = 'gzip';
      }
    } catch {
      body = asset.raw;
      delete baseHeaders['Content-Encoding'];
    }
  }

  if (res.writableEnded || res.destroyed) return;
  res.writeHead(200, { ...baseHeaders, 'Content-Length': body.length });
  res.end(isHead ? undefined : body);
}

/** Pre-compresses the heavy startup files so the first phone to connect does not pay for it. */
export function warmStaticCache(staticDir: string | undefined): void {
  if (!staticDir) return;
  const targets = ['index.html', 'flutter_bootstrap.js', 'main.dart.js', path.join('canvaskit', 'canvaskit.wasm'), path.join('canvaskit', 'canvaskit.js')];
  setTimeout(() => {
    void (async () => {
      for (const rel of targets) {
        try {
          const filePath = path.join(staticDir, rel);
          if (!fs.existsSync(filePath)) continue;
          const stat = fs.statSync(filePath);
          if (stat.size > MAX_CACHED_FILE_BYTES) continue;
          const asset = loadAsset(filePath, stat, specialContent(filePath).transform);
          await brotli(asset);
        } catch {
          // best effort
        }
      }
    })();
  }, 1500).unref?.();
}
