import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { isLoopbackHost } from './origin.js';
import { getPiCrustBaseDir } from '../config/config.js';
import type { RemoteManager } from '../remote/RemoteManager.js';

export interface StaticServerOptions {
  staticDir?: string;
  version: string;
  token: string | (() => string);
  remoteManager?: RemoteManager;
  listener?: 'local' | 'remote';
}

export function findStaticDir(customDir?: string): string | undefined {
  if (customDir && fs.existsSync(customDir)) return customDir;
  if (process.env.PI_CRUST_WEB_DIR && fs.existsSync(process.env.PI_CRUST_WEB_DIR)) {
    return process.env.PI_CRUST_WEB_DIR;
  }

  const baseDir = getPiCrustBaseDir();
  const userWebDir = path.join(baseDir, 'web');
  if (fs.existsSync(userWebDir)) return userWebDir;

  const scriptDir = typeof __dirname !== 'undefined' ? __dirname : '';
  const candidates = [
    path.join(process.cwd(), 'apps', 'pi_crust', 'build', 'web'),
    path.join(process.cwd(), 'build', 'web'),
    path.resolve(scriptDir, '..', '..', 'pi_crust', 'build', 'web'),
    path.resolve(scriptDir, '..', '..', '..', 'apps', 'pi_crust', 'build', 'web'),
    path.resolve(scriptDir, 'web')
  ];

  for (const c of candidates) {
    if (c && fs.existsSync(c)) return c;
  }
  return undefined;
}

const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.map': 'application/json; charset=utf-8'
};

export function setSecurityHeaders(
  res: http.ServerResponse,
  opts?: { listener?: 'local' | 'remote'; expectedHost?: string }
): void {
  const isRemote = opts?.listener === 'remote';
  if (isRemote) {
    const host = opts?.expectedHost;
    const connectSrc = host
      ? `'self' https://${host} wss://${host} blob: data:`
      : "'self' blob: data:";
    res.setHeader(
      'Content-Security-Policy',
      `default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' blob:; style-src 'self' 'unsafe-inline'; connect-src ${connectSrc}; img-src 'self' data: blob:; font-src 'self' data:; worker-src 'self' blob:; child-src 'self' blob:;`
    );
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  } else {
    res.setHeader(
      'Content-Security-Policy',
      "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' blob:; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://127.0.0.1:* http://127.0.0.1:* ws://localhost:* http://localhost:* blob: data:; img-src 'self' data: blob:; font-src 'self' data:; worker-src 'self' blob:; child-src 'self' blob:;"
    );
  }
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Content-Type-Options', 'nosniff');
}

export function serveStaticFile(
  req: http.IncomingMessage,
  res: http.ServerResponse,
  opts: StaticServerOptions
): boolean {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return false;
  }

  const isRemote = opts.listener === 'remote';

  if (isRemote) {
    if (!opts.remoteManager || !opts.remoteManager.isRemoteHostAllowed(req.headers.host)) {
      res.writeHead(403);
      res.end('Untrusted Host');
      return true;
    }
  } else {
    if (!isLoopbackHost(req.headers.host, req.socket.localPort || 80)) {
      res.writeHead(403);
      res.end('Untrusted Host');
      return true;
    }
  }

  const staticDir = findStaticDir(opts.staticDir);
  const getToken = () => (typeof opts.token === 'function' ? opts.token() : opts.token);

  // Apply required security headers
  const expectedHost = req.headers.host?.trim();
  setSecurityHeaders(res, { listener: opts.listener, expectedHost });

  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`);

  // Loopback cookie bootstrap on root request ONLY for local listener
  if (!isRemote && (url.pathname === '/' || url.pathname === '/index.html')) {
    const token = getToken();
    if (token) {
      res.setHeader('Set-Cookie', `pcp_token=${token}; Path=/; HttpOnly; SameSite=Strict`);
    }
  }

  // If no custom static directory configured or directory does not exist, return fallback HTML
  if (!staticDir || !fs.existsSync(staticDir)) {
    if (url.pathname === '/' || url.pathname === '/index.html') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Pi-Crust</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #11141b; color: #f0f3f8; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .card { background: #1a1e28; padding: 32px; border-radius: 12px; border: 1px solid #2d3446; text-align: center; max-width: 420px; }
    h1 { margin-top: 0; color: #7c9cfc; font-size: 20px; }
    p { color: #8c97ad; font-size: 13px; line-height: 1.5; }
    .status { display: inline-block; padding: 4px 10px; background: rgba(124, 156, 252, 0.15); color: #7c9cfc; border-radius: 6px; font-weight: 600; font-size: 11px; margin-top: 12px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Pi-Crust Daemon</h1>
    <p>Il daemon locale è attivo e operativo su loopback.</p>
    <div class="status">v${opts.version} • ONLINE</div>
  </div>
</body>
</html>`);
      return true;
    }
    return false;
  }

  // Sanitize pathname to prevent directory traversal
  let safePath = path.normalize(url.pathname).replace(/^(\.\.[\/\\])+/, '');
  if (safePath === '/' || safePath === '\\') {
    safePath = 'index.html';
  }

  const filePath = path.join(staticDir, safePath);

  // Security check: ensure path stays inside staticDir
  const relative = path.relative(staticDir, filePath);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    res.writeHead(403, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: false, error: 'Forbidden' }));
    return true;
  }

  // Check if file exists
  if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': contentType });
    if (req.method === 'HEAD') {
      res.end();
    } else {
      fs.createReadStream(filePath).pipe(res);
    }
    return true;
  }

  // SPA fallback to index.html if path has no file extension
  if (!path.extname(url.pathname)) {
    const indexPath = path.join(staticDir, 'index.html');
    if (fs.existsSync(indexPath)) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      if (req.method === 'HEAD') {
        res.end();
      } else {
        fs.createReadStream(indexPath).pipe(res);
      }
      return true;
    }
  }

  return false;
}
