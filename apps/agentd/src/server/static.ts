import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';

export interface StaticServerOptions {
  staticDir?: string;
  version: string;
  token: string | (() => string);
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

export function setSecurityHeaders(res: http.ServerResponse): void {
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://127.0.0.1:* http://127.0.0.1:* ws://localhost:* http://localhost:*; img-src 'self' data: blob:; font-src 'self' data:;"
  );
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

  const staticDir = opts.staticDir;
  const getToken = () => (typeof opts.token === 'function' ? opts.token() : opts.token);

  // Apply required security headers
  setSecurityHeaders(res);

  // Loopback cookie bootstrap on root request
  const ip = req.socket.remoteAddress;
  const isLoopback = ip === '127.0.0.1' || ip === '::1' || ip === '::ffff:127.0.0.1';
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`);

  if (isLoopback && (url.pathname === '/' || url.pathname === '/index.html')) {
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
