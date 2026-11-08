import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';
import { getPiFrameBaseDir } from '../config/config.js';

/**
 * Attachment uploads from the phone / browser client.
 *
 * A browser cannot hand the agent a file path on the daemon host, so the web client uploads the bytes
 * here first and then references the returned absolute `path` in its prompt. Each upload lives in
 * `<base>/blobs/<blobId>/<safeName>` so the agent sees a meaningful file name and extension.
 */

export const MAX_BLOB_BYTES = 50 * 1024 * 1024;
const BLOB_MAX_AGE_MS = 14 * 24 * 60 * 60 * 1000;
const BLOB_ID_RE = /^blob_[a-f0-9]{32}$/;

const MIME_BY_EXT: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.bmp': 'image/bmp',
  '.svg': 'image/svg+xml',
  '.heic': 'image/heic',
  '.pdf': 'application/pdf',
  '.txt': 'text/plain; charset=utf-8',
  '.md': 'text/plain; charset=utf-8',
  '.json': 'application/json'
};
const EXT_BY_MIME: Record<string, string> = {
  'image/png': '.png',
  'image/jpeg': '.jpg',
  'image/gif': '.gif',
  'image/webp': '.webp',
  'image/bmp': '.bmp',
  'image/heic': '.heic',
  'application/pdf': '.pdf',
  'text/plain': '.txt'
};

export function getBlobsDir(): string {
  const dir = path.join(getPiFrameBaseDir(), 'blobs');
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch {
    // reported when writing
  }
  return dir;
}

/** Turns the client supplied name into a safe single path segment (never a path). */
export function safeBlobName(rawHeader: string | undefined, contentType: string | undefined): string {
  let decoded = '';
  if (rawHeader) {
    try {
      decoded = decodeURIComponent(rawHeader);
    } catch {
      decoded = rawHeader;
    }
  }
  const base = decoded.replace(/\\/g, '/').split('/').pop() ?? '';
  let name = base.replace(/[^A-Za-z0-9._ -]/g, '_').replace(/^\.+/, '').trim().slice(0, 100);
  const mime = (contentType ?? '').split(';')[0].trim().toLowerCase();
  if (!name) name = 'file';
  if (!/\.[A-Za-z0-9]{1,8}$/.test(name) && EXT_BY_MIME[mime]) name += EXT_BY_MIME[mime];
  return name;
}

function json(res: http.ServerResponse, status: number, body: unknown): void {
  if (res.headersSent) return;
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}

/** POST /api/blobs: stores the request body and answers with the blob id and absolute path. */
export function receiveBlob(req: http.IncomingMessage, res: http.ServerResponse): void {
  const declared = Number(req.headers['content-length']);
  if (Number.isFinite(declared) && declared > MAX_BLOB_BYTES) {
    json(res, 413, { ok: false, error: 'Payload Too Large (max 50MB)' });
    req.resume();
    return;
  }

  const contentType = (req.headers['content-type'] as string | undefined) || 'application/octet-stream';
  const name = safeBlobName(req.headers['x-file-name'] as string | undefined, contentType);
  const blobId = `blob_${crypto.randomBytes(16).toString('hex')}`;
  const dir = path.join(getBlobsDir(), blobId);
  const target = path.join(dir, name);

  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch (err: any) {
    json(res, 500, { ok: false, error: err.message });
    req.resume();
    return;
  }

  const out = fs.createWriteStream(target);
  let total = 0;
  let aborted = false;
  const discard = () => {
    out.destroy();
    fs.rm(dir, { recursive: true, force: true }, () => {});
  };

  req.on('data', (chunk: Buffer) => {
    total += chunk.length;
    if (!aborted && total > MAX_BLOB_BYTES) {
      aborted = true;
      json(res, 413, { ok: false, error: 'Payload Too Large (max 50MB)' });
      req.unpipe(out);
      req.resume();
      discard();
    }
  });
  req.on('aborted', () => {
    aborted = true;
    discard();
  });
  req.pipe(out);

  out.on('finish', () => {
    if (aborted) return;
    json(res, 201, { ok: true, blobId, name, path: target, size: total, mimeType: contentType });
  });
  out.on('error', (err) => {
    if (aborted) return;
    aborted = true;
    json(res, 500, { ok: false, error: err.message });
    discard();
  });
}

/** GET /api/blobs/:blobId (also accepts legacy flat blob files). */
export function sendBlob(req: http.IncomingMessage, res: http.ServerResponse, rawName: string): void {
  const id = path.basename(rawName);
  if (!BLOB_ID_RE.test(id)) {
    json(res, 404, { ok: false, error: 'Blob not found' });
    return;
  }
  const entry = path.join(getBlobsDir(), id);
  let file: string | undefined;
  try {
    const stat = fs.statSync(entry);
    if (stat.isFile()) {
      file = entry;
    } else if (stat.isDirectory()) {
      const first = fs.readdirSync(entry).find((f) => fs.statSync(path.join(entry, f)).isFile());
      if (first) file = path.join(entry, first);
    }
  } catch {
    // not found
  }
  if (!file) {
    json(res, 404, { ok: false, error: 'Blob not found' });
    return;
  }
  const mime = MIME_BY_EXT[path.extname(file).toLowerCase()] ?? 'application/octet-stream';
  res.writeHead(200, {
    'Content-Type': mime,
    'Cache-Control': 'private, max-age=86400',
    'Content-Disposition': 'inline',
    // Uploaded content is untrusted: never let a browser run it as part of the app origin.
    'Content-Security-Policy': "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; sandbox",
    'X-Content-Type-Options': 'nosniff'
  });
  if (req.method === 'HEAD') res.end();
  else fs.createReadStream(file).pipe(res);
}

/** Deletes uploads older than two weeks so the folder does not grow forever. */
export function pruneOldBlobs(now = Date.now()): void {
  try {
    const dir = getBlobsDir();
    for (const entry of fs.readdirSync(dir)) {
      const full = path.join(dir, entry);
      try {
        if (now - fs.statSync(full).mtimeMs > BLOB_MAX_AGE_MS) fs.rmSync(full, { recursive: true, force: true });
      } catch {
        // best effort
      }
    }
  } catch {
    // best effort
  }
}
