import { test } from 'node:test';
import * as assert from 'node:assert';
import * as http from 'node:http';
import * as os from 'node:os';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { WebSocket } from 'ws';
import { validateCustomTunnelUrl, validateCustomTunnelCommand, validateRemotePatch, DEFAULT_CONFIG } from '../../config/config.js';
import { parseCommandLine } from '../TunnelProvider.js';
import { RemoteAuthManager } from '../RemoteAuthManager.js';
import { RemoteManager } from '../RemoteManager.js';
import { createHttpServer } from '../../server/httpServer.js';
import { createWsServer } from '../../server/wsServer.js';

test('Security: validateCustomTunnelUrl and validateCustomTunnelCommand enforce strict syntax', () => {
  // Valid https
  assert.strictEqual(validateCustomTunnelUrl('https://my-tunnel.example.com/'), 'https://my-tunnel.example.com');
  assert.strictEqual(validateCustomTunnelUrl('https://tunnel.example.com:8443/path'), 'https://tunnel.example.com:8443');

  // Reject non-https
  assert.throws(() => validateCustomTunnelUrl('http://my-tunnel.example.com'), /must use https/);
  assert.throws(() => validateCustomTunnelUrl('ftp://my-tunnel.example.com'), /must use https/);

  // Reject credentials
  assert.throws(() => validateCustomTunnelUrl('https://admin:secret@tunnel.example.com'), /must not contain credentials/);

  // Reject loopback addresses
  assert.throws(() => validateCustomTunnelUrl('https://localhost'), /loopback/);
  assert.throws(() => validateCustomTunnelUrl('https://127.0.0.1'), /loopback/);
  assert.throws(() => validateCustomTunnelUrl('https://127.0.1.5'), /loopback/);
  assert.throws(() => validateCustomTunnelUrl('https://[::1]'), /loopback/);
  assert.throws(() => validateCustomTunnelUrl('https://0.0.0.0'), /loopback/);

  // validateCustomTunnelCommand rejects control characters and newlines
  assert.strictEqual(validateCustomTunnelCommand('bore local $PORT --to example.com'), 'bore local $PORT --to example.com');
  assert.throws(() => validateCustomTunnelCommand('cmd.exe\ncalc.exe'), /single-line/);
  assert.throws(() => validateCustomTunnelCommand('cmd.exe\x00calc.exe'), /single-line/);

  // validateRemotePatch rejects unknown keys and bad types
  assert.throws(() => validateRemotePatch({ unknownKey: true }), /Unknown remote config key/);
  assert.throws(() => validateRemotePatch({ enabled: 'true' }), /boolean/);
  assert.throws(() => validateRemotePatch({ defaultMode: 'superuser' }), /invalid/);
});

test('Security: parseCommandLine parses argv without invoking a shell', () => {
  const parsed1 = parseCommandLine('cloudflared tunnel --url http://127.0.0.1:8080');
  assert.deepStrictEqual(parsed1, ['cloudflared', 'tunnel', '--url', 'http://127.0.0.1:8080']);

  const parsed2 = parseCommandLine('"C:\\Program Files\\Tailscale\\tailscale.exe" serve --https 443');
  assert.deepStrictEqual(parsed2, ['C:\\Program Files\\Tailscale\\tailscale.exe', 'serve', '--https', '443']);

  const parsed3 = parseCommandLine("bore local 8080 --to 'example.com'");
  assert.deepStrictEqual(parsed3, ['bore', 'local', '8080', '--to', 'example.com']);

  assert.throws(() => parseCommandLine('tailscale "unterminated quote'), /Unterminated quote/);
});

test('Security: 25 unauthenticated remote WS attempts do NOT block or delay local connections (H3)', async () => {
  const tmpDevices = path.join(os.tmpdir(), `pi_test_dos_dev_${Date.now()}.json`);
  const authManager = new RemoteAuthManager(tmpDevices);
  const remoteManager = new RemoteManager(DEFAULT_CONFIG, authManager);

  const masterToken = 'test_master_token_h3_isolation';
  let localPort = 0;
  let remotePort = 0;

  const localServer = createHttpServer({
    config: DEFAULT_CONFIG,
    token: masterToken,
    version: '1.3.0',
    startedAt: Date.now(),
    remoteManager,
    listener: 'local'
  });
  await new Promise<void>((r) => localServer.listen(0, '127.0.0.1', () => r()));
  localPort = (localServer.address() as any).port;

  const remoteServer = createHttpServer({
    config: DEFAULT_CONFIG,
    token: masterToken,
    version: '1.3.0',
    startedAt: Date.now(),
    remoteManager,
    listener: 'remote'
  });
  await new Promise<void>((r) => remoteServer.listen(0, '127.0.0.1', () => r()));
  remotePort = (remoteServer.address() as any).port;
  remoteManager.setListenerPort(remotePort);

  const { wss, manager } = createWsServer({
    httpServer: localServer,
    remoteHttpServer: remoteServer,
    config: DEFAULT_CONFIG,
    token: masterToken,
    version: '1.3.0',
    startedAt: Date.now(),
    port: localPort,
    remoteManager,
    piInfo: { path: '', version: '', supported: false },
    onCommand: async () => {}
  });

  const tunnelHost = 'remote-dos-test.example.com';
  await remoteManager.start({
    tunnelProvider: 'custom',
    customUrl: `https://${tunnelHost}`
  });

  try {
    // Blast 25 bad WS connections to the remote listener
    const badConnections: Promise<number>[] = [];
    for (let i = 0; i < 25; i++) {
      badConnections.push(new Promise<number>((resolve) => {
        const ws = new WebSocket(`ws://127.0.0.1:${remotePort}`, {
          headers: {
            Host: tunnelHost,
            Origin: `https://${tunnelHost}`
          }
        });
        ws.on('open', () => {
          ws.send(JSON.stringify({
            protocol: 1, kind: 'hello', id: `hl_bad_${i}`, ts: Date.now(),
            payload: { token: 'invalid_remote_token' }
          }));
        });
        ws.on('unexpected-response', (_, res) => {
          resolve(res.statusCode || 0);
        });
        ws.on('close', (code) => {
          resolve(code);
        });
        ws.on('error', () => {
          resolve(0);
        });
      }));
    }

    await Promise.all(badConnections);

    // CRITICAL: Local listener must still connect and authenticate IMMEDIATELY without 429
    const localWs = new WebSocket(`ws://127.0.0.1:${localPort}`);
    let localAuthenticated = false;

    await new Promise<void>((resolve, reject) => {
      localWs.on('open', () => {
        localWs.send(JSON.stringify({
          protocol: 1, kind: 'hello', id: 'hl_local', ts: Date.now(),
          type: 'connection.hello',
          payload: {
            token: masterToken,
            client: { name: 'desktop', version: '1.0' },
            encoding: 'json',
            capabilities: []
          }
        }));
      });
      localWs.on('message', (raw) => {
        const msg = JSON.parse(raw.toString());
        if (msg.kind === 'welcome') {
          localAuthenticated = true;
          localWs.close();
          resolve();
        }
      });
      localWs.on('unexpected-response', (_, res) => {
        reject(new Error(`Local connection unexpectedly rejected with HTTP ${res.statusCode}`));
      });
      localWs.on('error', reject);
    });

    assert.strictEqual(localAuthenticated, true);
  } finally {
    await remoteManager.stop().catch(() => {});
    wss.close();
    localServer.close();
    remoteServer.close();
    try { fs.unlinkSync(tmpDevices); } catch {}
  }
});

test('Security: remote.installCloudflared is blocked for remote connections', async () => {
  const { Dispatcher } = await import('../../commands/Dispatcher.js');
  const { SessionRegistry } = await import('../../sessions/SessionRegistry.js');
  const { ConnectionManager } = await import('../../server/wsServer.js');
  const { Connection } = await import('../../server/connection.js');

  const manager = new ConnectionManager();
  const registry = new SessionRegistry({
    piExecutablePath: 'node',
    capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 60000,
    connectionManager: manager
  });

  const tmpDev = path.join(os.tmpdir(), `pi_test_inst_cf_${Date.now()}.json`);
  const auth = new RemoteAuthManager(tmpDev);
  const rm = new RemoteManager(DEFAULT_CONFIG, auth);
  const disp = new Dispatcher(registry, manager, undefined, rm);

  const pairing = auth.generatePairing(60000);
  const paired = auth.pair(pairing.secret, 'Test Client', '127.0.0.1', 'control');

  const remoteWs = new (class extends (await import('node:events')).EventEmitter {
    readyState = 1;
    sentMessages: string[] = [];
    send(data: string, cb?: () => void) { this.sentMessages.push(data); cb?.(); }
    close() {}
  })();

  const remoteConn = new Connection({
    ws: remoteWs as any,
    expectedToken: 'tok',
    daemonVersion: '0.1.0',
    startedAt: Date.now(),
    piInfo: { path: 'node', version: '0.85.1', supported: true },
    remoteManager: rm,
    onCommand: async () => {},
    onClose: () => {}
  });
  remoteConn.state = 'ready';
  remoteConn.isRemote = true;
  remoteConn.deviceId = paired.deviceId;

  // Remote connection trying to trigger installation must be rejected with REMOTE_FORBIDDEN
  await disp.handle(remoteConn, {
    protocol: 1, kind: 'command', id: 'cmd_cf_rem', ts: Date.now(),
    commandId: 'c_cf_rem', type: 'remote.installCloudflared', payload: {}
  });

  const lastRes = remoteWs.sentMessages.map(m => JSON.parse(m)).find(m => m.kind === 'result');
  assert.ok(lastRes);
  assert.strictEqual(lastRes.payload.state, 'rejected');
  assert.ok(lastRes.payload.error.includes('not permitted'));

  try { fs.unlinkSync(tmpDev); } catch {}
});
