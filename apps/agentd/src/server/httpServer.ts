import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import * as crypto from 'node:crypto';
import { timingSafeEqualStrings, parseCookies } from './auth.js';
import type { DaemonConfig } from '../config/config.js';

export interface HttpServerOptions {
  config: DaemonConfig;
  token: string | (() => string);
  version: string;
  startedAt: number;
}

export function createHttpServer(opts: HttpServerOptions): http.Server {
  const { config, version, startedAt } = opts;
  const getToken = () => (typeof opts.token === 'function' ? opts.token() : opts.token);

  const blobsDir = path.join(os.homedir(), '.pi-crust', 'blobs');
  if (!fs.existsSync(blobsDir)) {
    try {
      fs.mkdirSync(blobsDir, { recursive: true });
    } catch {}
  }

  function isAuthorized(req: http.IncomingMessage): boolean {
    const currentToken = getToken();
    if (!currentToken) return false;

    const authHeader = req.headers['authorization'];
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const candidate = authHeader.slice(7).trim();
      if (timingSafeEqualStrings(candidate, currentToken)) {
        return true;
      }
    }
    const cookies = parseCookies(req.headers['cookie']);
    if (cookies['pcp_token'] && timingSafeEqualStrings(cookies['pcp_token'], currentToken)) {
      return true;
    }
    return false;
  }

  const server = http.createServer((req, res) => {
    const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`);

    // Set standard security headers
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');

    // 1. GET /api/health (unauthenticated)
    if (req.method === 'GET' && url.pathname === '/api/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(
        JSON.stringify({
          ok: true,
          version,
          pid: process.pid,
          uptime: Math.floor((Date.now() - startedAt) / 1000)
        })
      );
      return;
    }

    // 2. GET /api/session-bootstrap (allows local web UI to acquire token cookie)
    if (req.method === 'GET' && url.pathname === '/api/session-bootstrap') {
      const ip = req.socket.remoteAddress;
      const isLoopback = ip === '127.0.0.1' || ip === '::1' || ip === '::ffff:127.0.0.1';
      if (!isLoopback && !isAuthorized(req)) {
        res.writeHead(403, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'Forbidden' }));
        return;
      }

      const currentToken = getToken();
      res.writeHead(200, {
        'Content-Type': 'application/json',
        'Set-Cookie': `pcp_token=${currentToken}; Path=/; HttpOnly; SameSite=Strict`
      });
      res.end(JSON.stringify({ ok: true, token: currentToken }));
      return;
    }

    // 3. GET /api/themes (authenticated)
    if (req.method === 'GET' && url.pathname === '/api/themes') {
      if (!isAuthorized(req)) {
        res.writeHead(401, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'Unauthorized' }));
        return;
      }

      const themesDir = path.join(os.homedir(), '.pi-crust', 'themes');
      const themes: any[] = [];
      if (fs.existsSync(themesDir)) {
        try {
          const files = fs.readdirSync(themesDir);
          for (const file of files) {
            if (file.endsWith('.json')) {
              try {
                const content = fs.readFileSync(path.join(themesDir, file), 'utf8');
                themes.push(JSON.parse(content));
              } catch {}
            }
          }
        } catch {}
      }

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, themes }));
      return;
    }

    // 4. POST /api/blobs (authenticated)
    if (req.method === 'POST' && url.pathname === '/api/blobs') {
      if (!isAuthorized(req)) {
        res.writeHead(401, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'Unauthorized' }));
        return;
      }

      const blobId = `blob_${crypto.randomBytes(16).toString('hex')}`;
      const targetPath = path.join(blobsDir, blobId);
      const writeStream = fs.createWriteStream(targetPath);
      let totalBytes = 0;

      req.on('data', (chunk: Buffer) => {
        totalBytes += chunk.length;
        if (totalBytes > 50 * 1024 * 1024) { // 50 MB max limit
          res.writeHead(413, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, error: 'Payload Too Large (max 50MB)' }));
          req.destroy();
          writeStream.destroy();
          try { fs.unlinkSync(targetPath); } catch {}
        }
      });

      req.pipe(writeStream);

      writeStream.on('finish', () => {
        const mimeType = (req.headers['content-type'] as string) || 'application/octet-stream';
        res.writeHead(201, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, blobId, size: totalBytes, mimeType }));
      });

      writeStream.on('error', (err) => {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: err.message }));
      });
      return;
    }

    // 5. GET /api/blobs/:blobId (authenticated)
    if (req.method === 'GET' && url.pathname.startsWith('/api/blobs/')) {
      if (!isAuthorized(req)) {
        res.writeHead(401, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'Unauthorized' }));
        return;
      }

      const blobId = path.basename(url.pathname);
      const blobPath = path.join(blobsDir, blobId);
      if (!fs.existsSync(blobPath)) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'Blob not found' }));
        return;
      }

      res.writeHead(200, { 'Content-Type': 'application/octet-stream' });
      fs.createReadStream(blobPath).pipe(res);
      return;
    }

    // 6. Static files (e.g. Flutter Web hosting if enabled)
    if (req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(`<!DOCTYPE html><html><head><title>Pi-Crust Daemon</title></head><body><h1>Pi-Crust Daemon v${version}</h1><p>Status: Healthy</p></body></html>`);
      return;
    }

    res.writeHead(405, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: false, error: 'Method Not Allowed' }));
  });

  return server;
}
