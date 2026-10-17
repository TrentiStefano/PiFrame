import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import * as crypto from 'node:crypto';
import { timingSafeEqualStrings, parseCookies } from './auth.js';
import { serveStaticFile } from './static.js';
import { isLoopbackHost, isOriginAllowed, hasProxyHeaders } from './origin.js';
import type { DaemonConfig } from '../config/config.js';
import type { RemoteManager } from '../remote/RemoteManager.js';
import type { RemoteDeviceMode } from '../remote/types.js';

export interface HttpServerOptions {
  config: DaemonConfig;
  token: string | (() => string);
  version: string;
  startedAt: number;
  staticDir?: string;
  remoteManager?: RemoteManager;
  listener?: 'local' | 'remote';
}

function readJsonBody(req: http.IncomingMessage, maxBytes = 8192): Promise<any> {
  return new Promise((resolve, reject) => {
    let body = '';
    let byteCount = 0;
    let tooLarge = false;
    req.on('data', (chunk: Buffer) => {
      byteCount += chunk.length;
      if (byteCount > maxBytes) {
        tooLarge = true;
      } else {
        body += chunk.toString();
      }
    });
    req.on('end', () => {
      if (tooLarge) {
        return reject(Object.assign(new Error('Payload Too Large (max 8KB)'), { code: 'PAYLOAD_TOO_LARGE', status: 413 }));
      }
      try {
        const parsed = JSON.parse(body || '{}');
        resolve(parsed);
      } catch {
        reject(Object.assign(new Error('Invalid JSON payload'), { code: 'INVALID_JSON', status: 400 }));
      }
    });
    req.on('error', (err) => reject(err));
  });
}

export function createHttpServer(opts: HttpServerOptions): http.Server {
  const { config, version, startedAt } = opts;
  const isRemoteListener = opts.listener === 'remote';
  const getToken = () => (typeof opts.token === 'function' ? opts.token() : opts.token);

  const blobsDir = path.join(os.homedir(), '.pi-crust', 'blobs');
  if (!fs.existsSync(blobsDir)) {
    try {
      fs.mkdirSync(blobsDir, { recursive: true });
    } catch {}
  }

  // ---------------------------------------------------------------------------
  // Identity resolvers
  // ---------------------------------------------------------------------------

  /** Local listener: accepts master token or valid device token. */
  function getLocalIdentity(req: http.IncomingMessage): { isMaster: boolean; deviceId?: string; mode?: RemoteDeviceMode } | null {
    const currentToken = getToken();
    const cookies = parseCookies(req.headers['cookie']);
    const authHeader = req.headers['authorization'];
    const candidates: string[] = [];

    if (authHeader && authHeader.startsWith('Bearer ')) {
      candidates.push(authHeader.slice(7).trim());
    }
    if (cookies['pcp_token']) {
      candidates.push(cookies['pcp_token']);
    }
    if (cookies['pcp_device_token']) {
      candidates.push(cookies['pcp_device_token']);
    }

    for (const cand of candidates) {
      if (currentToken && timingSafeEqualStrings(cand, currentToken)) {
        return { isMaster: true, mode: 'control' };
      }
      if (opts.remoteManager) {
        const dev = opts.remoteManager.getAuthManager().verifyDeviceToken(cand);
        if (dev) {
          return { isMaster: false, deviceId: dev.deviceId, mode: dev.mode };
        }
      }
    }
    return null;
  }

  /** Remote listener: accepts ONLY valid device tokens. Master token is NEVER accepted (H2). */
  function getRemoteDeviceIdentity(req: http.IncomingMessage): { deviceId: string; mode: RemoteDeviceMode; tokenCandidate: string } | null {
    if (!opts.remoteManager) return null;
    const cookies = parseCookies(req.headers['cookie']);
    const authHeader = req.headers['authorization'];
    const candidates: string[] = [];

    if (authHeader && authHeader.startsWith('Bearer ')) {
      candidates.push(authHeader.slice(7).trim());
    }
    if (cookies['pcp_device_token']) {
      candidates.push(cookies['pcp_device_token']);
    }

    for (const cand of candidates) {
      const dev = opts.remoteManager.getAuthManager().verifyDeviceToken(cand);
      if (dev) {
        return { deviceId: dev.deviceId, mode: dev.mode, tokenCandidate: cand };
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Request Handler
  // ---------------------------------------------------------------------------

  const server = http.createServer((req, res) => {
    const localPort = req.socket.localPort || 80;

    // Standard baseline security headers
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Referrer-Policy', 'no-referrer');

    // -------------------------------------------------------------------------
    // REMOTE LISTENER
    // -------------------------------------------------------------------------
    if (isRemoteListener) {
      // Must pass tunnel host allowlist
      if (!opts.remoteManager || !opts.remoteManager.isRemoteHostAllowed(req.headers.host)) {
        res.writeHead(403, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'Untrusted Host' }));
        return;
      }

      // Check origin if present
      if (req.headers.origin && !opts.remoteManager.isRemoteOriginAllowed(req.headers.origin)) {
        res.writeHead(403, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'Untrusted Origin' }));
        return;
      }

      // HSTS header for all remote responses
      res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');

      const url = new URL(req.url ?? '/', `https://${req.headers.host}`);

      // 1. GET /api/health (minimal, no internal information leaked)
      if (req.method === 'GET' && url.pathname === '/api/health') {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
        res.end(JSON.stringify({ ok: true }));
        return;
      }

      // 2. GET /api/session-bootstrap
      if (req.method === 'GET' && url.pathname === '/api/session-bootstrap') {
        const identity = getRemoteDeviceIdentity(req);
        if (!identity) {
          res.writeHead(401, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
          res.end(JSON.stringify({
            ok: false,
            error: 'Unauthorized remote device. Pairing required.',
            needsPairing: true
          }));
          return;
        }

        res.writeHead(200, {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-store',
          'Set-Cookie': `pcp_device_token=${identity.tokenCandidate}; Path=/; HttpOnly; SameSite=Lax; Secure`
        });
        res.end(JSON.stringify({
          ok: true,
          token: identity.tokenCandidate,
          deviceId: identity.deviceId,
          mode: identity.mode
        }));
        return;
      }

      // 3. POST /api/remote/pair
      if (req.method === 'POST' && url.pathname === '/api/remote/pair') {
        const contentType = req.headers['content-type'] || '';
        if (!contentType.toLowerCase().includes('application/json')) {
          res.writeHead(415, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
          res.end(JSON.stringify({ ok: false, error: 'Content-Type must be application/json' }));
          return;
        }

        readJsonBody(req, 8192)
          .then((parsed) => {
            const candidate = typeof parsed.pairingSecret === 'string'
              ? parsed.pairingSecret.trim()
              : (typeof parsed.secret === 'string' ? parsed.secret.trim() : '');

            if (!candidate) {
              res.writeHead(400, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
              res.end(JSON.stringify({ ok: false, error: 'Missing pairingSecret' }));
              return;
            }

            const clientIp = opts.remoteManager!.getTrustedClientIp(req);
            const userAgent = typeof req.headers['user-agent'] === 'string' ? req.headers['user-agent'] : undefined;

            const result = opts.remoteManager!.pair(candidate, userAgent, clientIp);

            res.writeHead(200, {
              'Content-Type': 'application/json',
              'Cache-Control': 'no-store',
              'Set-Cookie': `pcp_device_token=${result.deviceToken}; Path=/; HttpOnly; SameSite=Lax; Secure`
            });
            res.end(JSON.stringify({
              ok: true,
              deviceId: result.deviceId,
              deviceToken: result.deviceToken,
              device: result.device
            }));
          })
          .catch((err: any) => {
            const status = err.status || (err.code === 'RATE_LIMITED' ? 429 : 401);
            res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
            res.end(JSON.stringify({ ok: false, error: err.message, code: err.code }));
          });
        return;
      }

      // 4. GET /api/remote/status
      if (req.method === 'GET' && url.pathname === '/api/remote/status') {
        const status = opts.remoteManager.getStatus();
        const identity = getRemoteDeviceIdentity(req);
        if (identity) {
          res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
          res.end(JSON.stringify({
            ok: true,
            enabled: status.enabled,
            state: status.state,
            mode: identity.mode
          }));
        } else {
          res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
          res.end(JSON.stringify({
            ok: true,
            enabled: status.enabled,
            state: status.state,
            needsPairing: true
          }));
        }
        return;
      }

      // 5. POST /api/blobs (allowed ONLY for devices in control mode)
      if (req.method === 'POST' && url.pathname === '/api/blobs') {
        const identity = getRemoteDeviceIdentity(req);
        if (!identity) {
          res.writeHead(401, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
          res.end(JSON.stringify({ ok: false, error: 'Unauthorized' }));
          return;
        }
        if (identity.mode !== 'control') {
          res.writeHead(403, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
          res.end(JSON.stringify({
            ok: false,
            code: 'REMOTE_FORBIDDEN',
            error: 'File uploads require control mode permission'
          }));
          return;
        }

        const blobId = `blob_${crypto.randomBytes(16).toString('hex')}`;
        const targetPath = path.join(blobsDir, blobId);
        const writeStream = fs.createWriteStream(targetPath);
        let totalBytes = 0;

        req.on('data', (chunk: Buffer) => {
          totalBytes += chunk.length;
          if (totalBytes > 50 * 1024 * 1024) {
            res.writeHead(413, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
            res.end(JSON.stringify({ ok: false, error: 'Payload Too Large (max 50MB)' }));
            req.destroy();
            writeStream.destroy();
            try { fs.unlinkSync(targetPath); } catch {}
          }
        });

        req.pipe(writeStream);

        writeStream.on('finish', () => {
          const mimeType = (req.headers['content-type'] as string) || 'application/octet-stream';
          res.writeHead(201, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
          res.end(JSON.stringify({ ok: true, blobId, size: totalBytes, mimeType }));
        });

        writeStream.on('error', (err) => {
          res.writeHead(500, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
          res.end(JSON.stringify({ ok: false, error: err.message }));
        });
        return;
      }

      // 6. GET /api/blobs/:blobId (authenticated remote device)
      if (req.method === 'GET' && url.pathname.startsWith('/api/blobs/')) {
        const identity = getRemoteDeviceIdentity(req);
        if (!identity) {
          res.writeHead(401, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
          res.end(JSON.stringify({ ok: false, error: 'Unauthorized' }));
          return;
        }

        const blobId = path.basename(url.pathname);
        const blobPath = path.join(blobsDir, blobId);
        if (!fs.existsSync(blobPath)) {
          res.writeHead(404, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
          res.end(JSON.stringify({ ok: false, error: 'Blob not found' }));
          return;
        }

        res.writeHead(200, { 'Content-Type': 'application/octet-stream' });
        fs.createReadStream(blobPath).pipe(res);
        return;
      }

      // 7. Static files (served over remote listener)
      if (req.method === 'GET' || req.method === 'HEAD') {
        const handled = serveStaticFile(req, res, {
          staticDir: opts.staticDir || process.env.PI_CRUST_WEB_DIR,
          version,
          token: opts.token,
          remoteManager: opts.remoteManager,
          listener: 'remote'
        });
        if (handled) return;
      }

      // Any other API or route is 404
      res.writeHead(404, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify({ ok: false, error: 'Not Found' }));
      return;
    }

    // -------------------------------------------------------------------------
    // LOCAL LISTENER (Default)
    // -------------------------------------------------------------------------

    // Host must strictly be loopback on this port
    if (!isLoopbackHost(req.headers.host, localPort)) {
      res.writeHead(403, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: 'Untrusted Host: local listener accepts loopback only' }));
      return;
    }

    // Reject ANY proxy headers on the local loopback listener (H2 defense)
    if (hasProxyHeaders(req)) {
      res.writeHead(403, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: 'Proxy headers forbidden on local loopback listener' }));
      return;
    }

    // Check Origin allowlist
    if (!isOriginAllowed(req.headers.origin, config.web?.origins || [], localPort)) {
      res.writeHead(403, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: 'Untrusted Origin' }));
      return;
    }

    const url = new URL(req.url ?? '/', `http://${req.headers.host}`);

    // 1. GET /api/health
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

    // 2. GET /api/session-bootstrap
    if (req.method === 'GET' && url.pathname === '/api/session-bootstrap') {
      const currentToken = getToken();
      res.writeHead(200, {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
        'Set-Cookie': `pcp_token=${currentToken}; Path=/; HttpOnly; SameSite=Strict`
      });
      res.end(JSON.stringify({ ok: true, token: currentToken, mode: 'local' }));
      return;
    }

    // 3. GET /api/remote/status
    if (req.method === 'GET' && url.pathname === '/api/remote/status') {
      if (!opts.remoteManager) {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
        res.end(JSON.stringify({ ok: true, enabled: false, state: 'stopped' }));
        return;
      }
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify({ ok: true, ...opts.remoteManager.getStatus() }));
      return;
    }

    // 4. GET /api/themes (authenticated)
    if (req.method === 'GET' && url.pathname === '/api/themes') {
      if (!getLocalIdentity(req)) {
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

    // 5. POST /api/blobs (authenticated)
    if (req.method === 'POST' && url.pathname === '/api/blobs') {
      const identity = getLocalIdentity(req);
      if (!identity) {
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
        if (totalBytes > 50 * 1024 * 1024) {
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

    // 6. GET /api/blobs/:blobId (authenticated)
    if (req.method === 'GET' && url.pathname.startsWith('/api/blobs/')) {
      if (!getLocalIdentity(req)) {
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

    // 7. Static files (local listener)
    if (req.method === 'GET' || req.method === 'HEAD') {
      const handled = serveStaticFile(req, res, {
        staticDir: opts.staticDir || process.env.PI_CRUST_WEB_DIR,
        version,
        token: opts.token,
        remoteManager: opts.remoteManager,
        listener: 'local'
      });
      if (handled) return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: false, error: 'Not Found' }));
  });

  return server;
}
