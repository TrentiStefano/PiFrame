import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { isLoopbackHost } from './origin.js';
import { getPiFrameBaseDir } from '../config/config.js';
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
  if (process.env.PI_FRAME_WEB_DIR && fs.existsSync(process.env.PI_FRAME_WEB_DIR)) {
    return process.env.PI_FRAME_WEB_DIR;
  }

  const baseDir = getPiFrameBaseDir();
  const userWebDir = path.join(baseDir, 'web');
  if (fs.existsSync(userWebDir) && fs.existsSync(path.join(userWebDir, 'index.html'))) {
    return userWebDir;
  }

  const scriptDir = typeof __dirname !== 'undefined' ? __dirname : '';
  const candidates: string[] = [
    path.join(process.cwd(), 'apps', 'pi_frame', 'build', 'web'),
    path.join(process.cwd(), 'build', 'web'),
    path.resolve(scriptDir, 'web'),
    path.resolve(scriptDir, 'data', 'web'),
    path.resolve(scriptDir, 'data', 'flutter_assets', 'web'),
  ];

  // Walk up from scriptDir (up to 8 levels) checking web directories
  let sDir = scriptDir;
  for (let i = 0; i < 8 && sDir && sDir !== path.dirname(sDir); i++) {
    candidates.push(path.join(sDir, 'web'));
    candidates.push(path.join(sDir, 'build', 'web'));
    candidates.push(path.join(sDir, 'apps', 'pi_frame', 'build', 'web'));
    sDir = path.dirname(sDir);
  }

  // Walk up from process.cwd() (up to 5 levels)
  let cDir = process.cwd();
  for (let i = 0; i < 5 && cDir && cDir !== path.dirname(cDir); i++) {
    candidates.push(path.join(cDir, 'web'));
    candidates.push(path.join(cDir, 'build', 'web'));
    candidates.push(path.join(cDir, 'apps', 'pi_frame', 'build', 'web'));
    cDir = path.dirname(cDir);
  }

  if (userWebDir && fs.existsSync(userWebDir)) {
    candidates.push(userWebDir);
  }

  for (const c of candidates) {
    if (c && fs.existsSync(c) && fs.existsSync(path.join(c, 'index.html'))) {
      return c;
    }
  }

  for (const c of candidates) {
    if (c && fs.existsSync(c)) {
      return c;
    }
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
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <title>PiFrame Daemon</title>
  <style>
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background: #161c27;
      color: #f1f5f9;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
      padding: 20px;
    }
    .card {
      background: #1e2638;
      padding: 32px 28px;
      border-radius: 16px;
      border: 1px solid #2e3a52;
      text-align: center;
      max-width: 440px;
      width: 100%;
      box-shadow: 0 16px 40px rgba(0, 0, 0, 0.35);
    }
    .logo {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 52px;
      height: 52px;
      border-radius: 14px;
      background: rgba(95, 159, 197, 0.12);
      border: 1px solid rgba(95, 159, 197, 0.25);
      margin-bottom: 16px;
    }
    .logo svg { width: 28px; height: 28px; fill: #5f9fc5; }
    h1 { margin: 0 0 8px 0; color: #f1f5f9; font-size: 21px; font-weight: 700; letter-spacing: -0.3px; }
    p { color: #94a3b8; font-size: 13.5px; line-height: 1.5; margin: 0 0 18px 0; }
    .status-row { display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 20px; }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 4px 12px;
      background: rgba(95, 159, 197, 0.12);
      color: #5f9fc5;
      border: 1px solid rgba(95, 159, 197, 0.3);
      border-radius: 8px;
      font-weight: 600;
      font-size: 11.5px;
    }
    .badge-dot { width: 6px; height: 6px; border-radius: 50%; background: #4ade80; display: inline-block; }
    .pair-box {
      margin-top: 16px;
      padding: 16px;
      background: rgba(15, 23, 42, 0.4);
      border-radius: 12px;
      border: 1px solid #2e3a52;
      text-align: left;
    }
    .pair-title { font-size: 12.5px; font-weight: 600; color: #e2e8f0; margin-bottom: 8px; }
    .pair-status { font-size: 12px; color: #94a3b8; line-height: 1.4; }
    .pair-status.success { color: #4ade80; font-weight: 600; }
    .pair-status.error { color: #f87171; }
    .pair-form { display: flex; gap: 8px; margin-top: 10px; }
    .pair-input {
      flex: 1;
      padding: 8px 12px;
      background: #161c27;
      border: 1px solid #2e3a52;
      border-radius: 8px;
      color: #f1f5f9;
      font-size: 13px;
      outline: none;
    }
    .pair-input:focus { border-color: #5f9fc5; }
    .pair-btn {
      padding: 8px 14px;
      background: #5f9fc5;
      color: #0f172a;
      border: none;
      border-radius: 8px;
      font-size: 12.5px;
      font-weight: 600;
      cursor: pointer;
    }
    .pair-btn:hover { background: #7ab3d6; }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">
      <svg viewBox="0 0 24 24"><path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/></svg>
    </div>
    <h1>PiFrame Daemon</h1>
    <p>${isRemote ? 'Connessione remota attiva e sicura.' : 'Il daemon locale è attivo e operativo su loopback.'}</p>
    <div class="status-row">
      <div class="badge"><span class="badge-dot"></span>v${opts.version} • ONLINE</div>
    </div>
    <div class="pair-box" id="pairBox">
      <div class="pair-title">Associazione Dispositivo</div>
      <div class="pair-status" id="pairStatus">Verifica codice di associazione in corso...</div>
      <div class="pair-form" id="pairForm" style="display: none;">
        <input type="text" class="pair-input" id="pinInput" placeholder="Inserisci codice PIN o secret" />
        <button class="pair-btn" id="pairBtn" onclick="submitPairing()">Associa</button>
      </div>
    </div>
  </div>
  <script>
    function doPair(secret) {
      var statusEl = document.getElementById('pairStatus');
      var formEl = document.getElementById('pairForm');
      statusEl.textContent = 'Associazione in corso...';
      statusEl.className = 'pair-status';

      fetch('/api/remote/pair', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pairingSecret: secret })
      })
      .then(function(r) { return r.json(); })
      .then(function(res) {
        if (res.ok && res.deviceToken) {
          try {
            sessionStorage.setItem('pcp_device_token', res.deviceToken);
            localStorage.setItem('pcp_device_token', res.deviceToken);
          } catch(e) {}
          statusEl.textContent = '✓ Dispositivo associato con successo! (Permessi: ' + (res.device ? res.device.mode : 'view') + ')';
          statusEl.className = 'pair-status success';
          if (formEl) formEl.style.display = 'none';
          setTimeout(function() { window.location.reload(); }, 1500);
        } else {
          statusEl.textContent = 'Errore: ' + (res.error || 'Codice non valido');
          statusEl.className = 'pair-status error';
          if (formEl) formEl.style.display = 'flex';
        }
      })
      .catch(function(err) {
        statusEl.textContent = 'Errore di connessione durante l\\'associazione.';
        statusEl.className = 'pair-status error';
        if (formEl) formEl.style.display = 'flex';
      });
    }

    function submitPairing() {
      var val = (document.getElementById('pinInput').value || '').trim();
      if (val) doPair(val);
    }

    (function() {
      var hash = window.location.hash || '';
      if (hash.startsWith('#')) hash = hash.slice(1);
      var params = new URLSearchParams(hash);
      var pairSecret = params.get('pair');
      if (pairSecret) {
        window.history.replaceState(null, '', window.location.pathname + window.location.search);
        doPair(pairSecret);
      } else {
        var statusEl = document.getElementById('pairStatus');
        var formEl = document.getElementById('pairForm');
        statusEl.textContent = 'Inquadra il codice QR da PiFrame sul desktop per associare questo dispositivo, oppure inserisci il codice:';
        formEl.style.display = 'flex';
      }
    })();
  </script>
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
