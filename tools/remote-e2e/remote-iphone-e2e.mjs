// Emulated-iPhone end-to-end check of the remote (phone) web app. See README.md.
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '../..');
const WS_REQUIRE = createRequire(path.join(REPO, 'apps/agentd/package.json'));
const WebSocket = WS_REQUIRE('ws');
const { chromium, webkit, devices } = createRequire(path.join(process.env.PF_E2E_DIR || path.join(os.homedir(), '.pf-e2e'), 'x.js'))('playwright');
const HOST = 'pf-remote.test';
const REMOTE_PORT = 47811;
const TLS_PORT = 47812;
const PROXY_PORT = 47813;
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pf-e2e-'));
execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj', '/CN=pf-remote.test', '-addext', 'subjectAltName=DNS:pf-remote.test', '-keyout', path.join(tmp, 'key.pem'), '-out', path.join(tmp, 'cert.pem')], { stdio: 'ignore', env: { ...process.env, MSYS_NO_PATHCONV: '1' } });
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'pf-home-'));
fs.writeFileSync(path.join(home, 'config.json'), JSON.stringify({
  remote: { enabled: true, tunnelProvider: 'custom', customTunnelUrl: `https://${HOST}`, defaultMode: 'control', listenerPort: REMOTE_PORT }
}));
const results = [];
const check = (name, ok, extra = '') => { results.push({ name, ok }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name} ${extra}`); };

let daemon;
async function startDaemon() {
  const piAgentDir = path.join(home, 'pi-agent');
  const sessionsDir = path.join(piAgentDir, 'sessions');
  fs.mkdirSync(sessionsDir, { recursive: true });
  daemon = spawn('node', [`${REPO}/apps/agentd/dist/pi-agentd.cjs`], {
    env: {
      ...process.env,
      PI_FRAME_HOME: home,
      PI_FRAME_WEB_DIR: `${REPO}/apps/pi_frame/build/web`,
      PI_CODING_AGENT_DIR: piAgentDir,
      PI_CODING_AGENT_SESSION_DIR: sessionsDir,
      HOME: home,
      USERPROFILE: home,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  daemon.stdout.on('data', d => process.env.PF_LOG && process.stdout.write('[d] ' + d));
  daemon.stderr.on('data', d => process.stdout.write('[d!] ' + d));
  const rt = path.join(home, 'runtime', 'daemon.json');
  for (let i = 0; i < 100; i++) { if (fs.existsSync(rt) && fs.existsSync(path.join(home, 'runtime', 'daemon.token'))) break; await new Promise(r => setTimeout(r, 100)); }
  await new Promise(r => setTimeout(r, 1200));
  const info = JSON.parse(fs.readFileSync(rt, 'utf8'));
  return { port: info.port, token: fs.readFileSync(path.join(home, 'runtime', 'daemon.token'), 'utf8').trim() };
}
async function stopDaemon() {
  daemon.kill('SIGTERM'); await new Promise(r => setTimeout(r, 1500)); try { daemon.kill('SIGKILL'); } catch {}
  await new Promise(r => setTimeout(r, 500));
}
function generatePairing({ port, token }) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    ws.on('open', () => ws.send(JSON.stringify({ protocol: 1, kind: 'hello', id: 'h1', ts: Date.now(), type: 'connection.hello', payload: { token, client: { name: 'e2e', version: '0', platform: 'test' }, encoding: 'json', capabilities: [] } })));
    ws.on('message', (m) => {
      const msg = JSON.parse(m.toString());
      if (msg.kind === 'welcome') ws.send(JSON.stringify({ protocol: 1, kind: 'command', id: 'c1', ts: Date.now(), sessionId: '@daemon', commandId: 'cmd_pair_1', type: 'remote.generatePairing', payload: {} }));
      if (msg.kind === 'result' || msg.kind === 'error') { ws.close(); resolve(msg); }
    });
    ws.on('error', reject); setTimeout(() => reject(new Error('pair timeout')), 8000);
  });
}

// TLS terminator for pf-remote.test -> remote listener (keeps Host header), incl. WS upgrade
const tls = https.createServer({ key: fs.readFileSync(path.join(tmp, 'key.pem')), cert: fs.readFileSync(path.join(tmp, 'cert.pem')) }, (req, res) => {
  const p = http.request({ host: '127.0.0.1', port: REMOTE_PORT, path: req.url, method: req.method, headers: req.headers }, (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
  p.on('error', () => { res.writeHead(502); res.end(); }); req.pipe(p);
});
tls.on('upgrade', (req, sock, head) => {
  const up = net.connect(REMOTE_PORT, '127.0.0.1', () => {
    up.write(`${req.method} ${req.url} HTTP/1.1\r\n` + Object.entries(req.headers).map(([k, v]) => `${k}: ${v}`).join('\r\n') + '\r\n\r\n'); up.write(head);
    up.pipe(sock); sock.pipe(up);
  });
  up.on('error', () => sock.destroy()); sock.on('error', () => up.destroy());
});
tls.listen(TLS_PORT);
// Forward proxy: every CONNECT goes to the TLS terminator
const proxy = http.createServer((q, s) => { s.writeHead(405); s.end(); });
proxy.on('connect', (req, sock, head) => {
  const up = net.connect(TLS_PORT, '127.0.0.1', () => { sock.write('HTTP/1.1 200 Connection Established\r\n\r\n'); up.write(head); up.pipe(sock); sock.pipe(up); });
  up.on('error', () => sock.destroy()); sock.on('error', () => up.destroy());
});
proxy.listen(PROXY_PORT);

const deviceName = process.env.PF_E2E_DEVICE || 'iPhone 12';
// Playwright has no iPhone 18 profile yet; its 18 Pro screen matches the 17 Pro descriptor.
const deviceProfile = deviceName === 'iPhone 18 Pro' ? devices['iPhone 17 Pro'] : devices[deviceName];
if (!deviceProfile) throw new Error(`Unknown Playwright device profile: ${deviceName}`);
const fullScreenViewport = process.env.PF_E2E_FULL_SCREEN === '1';
const iphone = {
  ...deviceProfile,
  viewport: fullScreenViewport ? { ...deviceProfile.screen } : { ...deviceProfile.viewport },
  isMobile: fullScreenViewport ? false : deviceProfile.isMobile,
};
console.log(`Device profile: ${deviceName} (${iphone.viewport.width}x${iphone.viewport.height} CSS, DPR ${iphone.deviceScaleFactor}, ${fullScreenViewport ? 'full-screen viewport' : 'browser viewport'})`);
const engine = process.env.ENGINE === 'chromium' ? chromium : webkit;
const browser = await engine.launch({ proxy: { server: `http://127.0.0.1:${PROXY_PORT}` } });
const outDir = path.resolve(process.env.PF_E2E_SHOTS || path.join(HERE, 'shots')); fs.mkdirSync(outDir, { recursive: true });

async function newCtx() {
  const ctx = await browser.newContext({ ...iphone, ignoreHTTPSErrors: true, locale: 'it-IT' });
  await ctx.addInitScript(() => { window.__ff = 0; window.addEventListener('flutter-first-frame', () => { window.__ff = Math.round(performance.now()); }); });
  const page = await ctx.newPage();
  const transfers = [];
  page.on('response', async (r) => { try { const h = r.headers(); transfers.push({ url: r.url().replace(`https://${HOST}`, ''), status: r.status(), enc: h['content-encoding'] || '-', len: Number(h['content-length'] || 0) }); } catch {} });
  page.on('console', m => { if (process.env.PF_LOG || m.type() === 'error') console.log('[page]', m.type(), m.text().slice(0, 200)); });
  page.on('pageerror', e => console.log('[pageerror]', String(e).slice(0, 200)));
  return { ctx, page, transfers };
}
const firstFrame = async (page) => { try { await page.waitForFunction(() => window.__ff > 0, null, { timeout: 60000 }); return await page.evaluate(() => window.__ff); } catch { return 0; } };

try {
  let d = await startDaemon();
  console.log('daemon up', d.port);

  // A. unpaired visit -> real message, not a blank page
  { const { ctx, page } = await newCtx();
    await page.goto(`https://${HOST}/`, { waitUntil: 'load' });
    await page.waitForSelector('#pf-status', { timeout: 15000 }).catch(() => {});
    const txt = await page.locator('#pf-status').innerText().catch(() => '');
    check('A. unpaired phone shows re-pair message (no blank page)', /Associa di nuovo/.test(txt), JSON.stringify(txt.slice(0, 60)));
    await page.screenshot({ path: `${outDir}/A-unpaired.png` }); await ctx.close(); }

  // B. pair + load
  const pairRes = await generatePairing(d);
  const pairUrl = pairRes.payload?.url || pairRes.payload?.data?.url;
  check('B0. daemon produced a pairing URL', !!pairUrl, String(pairUrl).slice(0, 50));
  const secretHash = new URL(pairUrl).hash;
  const { ctx, page, transfers } = await newCtx();
  let t0 = Date.now();
  await page.goto(`https://${HOST}/${secretHash}`, { waitUntil: 'commit' });
  const ok = await firstFrame(page); const tFirst = Date.now() - t0;
  check('B. paired phone reaches first Flutter frame', ok > 0, `${ok}ms since navigation start (wall ${tFirst}ms)`);
  await page.waitForTimeout(2500);
  await page.screenshot({ path: `${outDir}/B-paired.png` });
  const heavy = transfers.filter(t => /main\.dart\.js|canvaskit\.wasm|flutter_bootstrap/.test(t.url));
  console.log('   transfers:', heavy.map(t => `${t.url} ${t.enc} ${t.len}`).join(' | '));
  check('B2. heavy assets are brotli/gzip compressed', heavy.length > 0 && heavy.every(t => t.enc !== '-'));
  const sw = await page.evaluate(async () => (await navigator.serviceWorker?.getRegistrations?.() || []).length);
  check('B3. no service worker registered', sw === 0, `regs=${sw}`);
  const ws = await page.evaluate(() => performance.getEntriesByType('resource').filter(e => e.name.startsWith('wss')).length).catch(() => 0);

  // C. reload (repeat visit uses 304s)
  transfers.length = 0; t0 = Date.now();
  await page.reload({ waitUntil: 'commit' }); const ok2 = await firstFrame(page);
  check('C. reload of paired phone works', ok2 > 0, `${ok2}ms`);
  console.log('   reload transfers:', transfers.filter(t => /main\.dart|canvaskit\.wasm/.test(t.url)).map(t => `${t.url} ${t.status}`).join(' | '));

  // D. daemon restart (simulates app/daemon update): still paired, loads
  await stopDaemon(); d = await startDaemon();
  transfers.length = 0; t0 = Date.now();
  await page.goto(`https://${HOST}/`, { waitUntil: 'commit' });
  const ok3 = await firstFrame(page);
  check('D. after daemon restart the phone is still paired and loads', ok3 > 0, `${ok3}ms`);
  await page.waitForTimeout(2500);
  await page.screenshot({ path: `${outDir}/D-after-restart.png` });
  const needs = await page.locator('#pf-status').count();
  check('D2. no re-pair/offline panel after restart', needs === 0);

  // E. viewport/scroll pinning + tap alignment
  const vp = await page.evaluate(() => ({ y: window.pageYOffset, vv: window.visualViewport ? [window.visualViewport.offsetTop, window.visualViewport.scale] : null, pos: getComputedStyle(document.body).position }));
  check('E1. body is pinned and viewport has no offset', vp.y === 0 && vp.pos === 'fixed' && (!vp.vv || (vp.vv[0] === 0 && vp.vv[1] === 1)), JSON.stringify(vp));
  await page.evaluate(() => { window.scrollTo(0, 80); });
  await page.waitForTimeout(300);
  const y2 = await page.evaluate(() => window.pageYOffset);
  check('E2. forced page scroll is reset to 0', y2 === 0, `y=${y2}`);
  await page.evaluate(() => { window.__taps = []; document.addEventListener('pointerdown', e => window.__taps.push([Math.round(e.clientX), Math.round(e.clientY)]), true); });
  const pts = [[195, 120], [100, 400], [300, 700]];
  for (const [x, y] of pts) { await page.touchscreen.tap(x, y); await page.waitForTimeout(150); }
  const taps = await page.evaluate(() => window.__taps);
  const aligned = taps.length >= 3 && pts.every(([x, y], i) => taps[i] && Math.abs(taps[i][0] - x) <= 1 && Math.abs(taps[i][1] - y) <= 1);
  check('E3. touch coordinates reach the page unshifted', aligned, JSON.stringify(taps));
  await page.screenshot({ path: `${outDir}/E-after-taps.png` });

  // E4. attachment upload from the phone: bytes go to the daemon and come back through the tunnel
  const upload = await page.evaluate(async () => {
    const bytes = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3]);
    const post = await fetch('/api/blobs', { method: 'POST', headers: { 'Content-Type': 'image/png', 'X-File-Name': encodeURIComponent('IMG 7660.png') }, body: bytes });
    const info = await post.json();
    const get = await fetch('/api/blobs/' + info.blobId);
    const back = new Uint8Array(await get.arrayBuffer());
    return { status: post.status, info, getStatus: get.status, type: get.headers.get('content-type'), same: back.length === bytes.length && back.every((b, i) => b === bytes[i]) };
  });
  check('E4. phone upload is stored on the host with its name and extension', upload.status === 201 && /IMG 7660.png$/.test(upload.info.path || ''), JSON.stringify({ status: upload.status, path: upload.info.path }));
  check('E5. uploaded image is served back unchanged as image/png', upload.getStatus === 200 && upload.type === 'image/png' && upload.same);
  check('E6. the stored file exists on the daemon host', fs.existsSync(upload.info.path));

  // F. lost credential -> clear message
  await page.evaluate(() => { localStorage.clear(); sessionStorage.clear(); });
  await ctx.clearCookies();
  await page.goto(`https://${HOST}/`, { waitUntil: 'load' });
  await page.waitForSelector('#pf-status', { timeout: 15000 }).catch(() => {});
  check('F. lost credential shows re-pair message', /Associa di nuovo/.test(await page.locator('#pf-status').innerText().catch(() => '')));

  // G. network drops after the shell loaded -> offline panel (not a blank page)
  d = await startDaemon();
  const g = await newCtx();
  await g.page.route('**/api/session-bootstrap', r => r.abort());
  await g.page.goto(`https://${HOST}/`, { waitUntil: 'load' }).catch(() => {});
  await g.page.waitForSelector('#pf-status', { timeout: 20000 }).catch(() => {});
  check('G. unreachable computer shows offline message', /non raggiungibile/.test(await g.page.locator('#pf-status').innerText().catch(() => '')));
  await g.page.screenshot({ path: `${outDir}/G-offline.png` });
} catch (e) { console.log('HARNESS ERROR', e); results.push({ name: 'harness', ok: false }); }
finally {
  await browser.close().catch(() => {}); try { daemon.kill('SIGKILL'); } catch {}
  tls.close(); proxy.close();
  console.log(`\n${results.filter(r => r.ok).length}/${results.length} passed`);
  process.exit(results.every(r => r.ok) ? 0 : 1);
}
