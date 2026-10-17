import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as http from 'node:http';
import * as path from 'node:path';
import * as fs from 'node:fs';
import * as os from 'node:os';
import { fileURLToPath } from 'node:url';
import WebSocket from 'ws';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Import agentd components
import { createHttpServer } from '../../../apps/agentd/dist/server/httpServer.js';
import { createWsServer } from '../../../apps/agentd/dist/server/wsServer.js';
import { SessionRegistry } from '../../../apps/agentd/dist/sessions/SessionRegistry.js';
import { Dispatcher } from '../../../apps/agentd/dist/commands/Dispatcher.js';
import { DEFAULT_CONFIG } from '../../../apps/agentd/dist/config/config.js';
import { RemoteManager } from '../../../apps/agentd/dist/remote/RemoteManager.js';
import { RemoteAuthManager } from '../../../apps/agentd/dist/remote/RemoteAuthManager.js';

test('E2E: Safe Remote Connection - Dedicated Listener, Pairing, Modes & Revocation', async () => {
  const fakePiPath = path.resolve(__dirname, '../../../tools/fake-pi/dist/index.js');
  const tmpDevices = path.join(os.tmpdir(), `pi_e2e_remote_${Date.now()}.json`);
  const authManager = new RemoteAuthManager(tmpDevices);
  const remoteManager = new RemoteManager(DEFAULT_CONFIG, authManager);

  const masterToken = 'test_master_local_only_token_256bit';
  const version = '1.3.0';
  const startedAt = Date.now();

  let localPort = 0;
  let remotePort = 0;

  // Local listener
  const httpServer = createHttpServer({
    config: DEFAULT_CONFIG,
    token: masterToken,
    version,
    startedAt,
    remoteManager,
    listener: 'local'
  });

  await new Promise<void>((resolve, reject) => {
    httpServer.listen(0, '127.0.0.1', () => resolve());
    httpServer.on('error', reject);
  });
  localPort = (httpServer.address() as any).port;

  // Dedicated remote listener
  const remoteHttpServer = createHttpServer({
    config: DEFAULT_CONFIG,
    token: masterToken,
    version,
    startedAt,
    remoteManager,
    listener: 'remote'
  });

  await new Promise<void>((resolve, reject) => {
    remoteHttpServer.listen(0, '127.0.0.1', () => resolve());
    remoteHttpServer.on('error', reject);
  });
  remotePort = (remoteHttpServer.address() as any).port;
  remoteManager.setListenerPort(remotePort);

  let registry!: SessionRegistry;
  let dispatcher!: Dispatcher;

  const { wss, manager } = createWsServer({
    httpServer,
    remoteHttpServer,
    config: DEFAULT_CONFIG,
    token: masterToken,
    version,
    startedAt,
    remoteManager,
    piInfo: { path: fakePiPath, version: '0.85.1', supported: true },
    port: localPort,
    onCommand: async (conn, cmd) => {
      await dispatcher.handle(conn, cmd);
    },
    onAttach: async (conn, sid, lastSeq) => {
      await registry.attachClient(sid, conn, lastSeq);
    },
    onDetach: async (conn, sid) => {
      await registry.detachClient(sid, conn);
    },
  });

  registry = new SessionRegistry({
    piExecutablePath: fakePiPath,
    capabilities: {
      version: '0.85.1',
      supported: true,
      modes: ['rpc'],
      features: [],
    },
    workerIdleTimeoutMs: 60000,
    connectionManager: manager,
  });

  dispatcher = new Dispatcher(registry, manager, undefined, remoteManager);

  try {
    // 1. Enable remote access with a simulated tunnel URL
    const tunnelHost = ['phone-session-e2e', 'tunnel-test.internal'].join('.');
    const tunnelUrl = `https://${tunnelHost}`;

    await remoteManager.start({
      tunnelProvider: 'custom',
      customUrl: tunnelUrl,
    });

    const status = remoteManager.getStatus();
    assert.strictEqual(status.enabled, true);
    assert.strictEqual(status.url, tunnelUrl);
    assert.ok(status.pairingPending);

    // 2. Unauthenticated remote caller requesting bootstrap is rejected (401 needsPairing)
    const unauthRes = await new Promise<any>((resolve, reject) => {
      const req = http.request({
        host: '127.0.0.1',
        port: remotePort,
        path: '/api/session-bootstrap',
        headers: {
          Host: tunnelHost,
        },
      }, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => resolve({ status: res.statusCode, data: JSON.parse(body) }));
      });
      req.on('error', reject);
      req.end();
    });

    assert.strictEqual(unauthRes.status, 401);
    assert.strictEqual(unauthRes.data.needsPairing, true);
    assert.strictEqual(unauthRes.data.ok, false);

    // 3. Brute force protection on /api/remote/pair: 5 failures locks out IP
    for (let i = 0; i < 4; i++) {
      await new Promise<void>((resolve, reject) => {
        const payload = JSON.stringify({ pairingSecret: 'invalid_secret' });
        const req = http.request({
          host: '127.0.0.1',
          port: remotePort,
          path: '/api/remote/pair',
          method: 'POST',
          headers: {
            Host: tunnelHost,
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(payload),
          },
        }, (res) => {
          assert.strictEqual(res.statusCode, 401);
          res.resume();
          res.on('end', () => resolve());
        });
        req.on('error', reject);
        req.write(payload);
        req.end();
      });
    }

    // 5th attempt locks out the IP
    await new Promise<void>((resolve, reject) => {
      const payload = JSON.stringify({ pairingSecret: 'invalid_secret' });
      const req = http.request({
        host: '127.0.0.1',
        port: remotePort,
        path: '/api/remote/pair',
        method: 'POST',
        headers: {
          Host: tunnelHost,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
        },
      }, (res) => {
        assert.strictEqual(res.statusCode, 401);
        res.resume();
        res.on('end', () => resolve());
      });
      req.on('error', reject);
      req.write(payload);
      req.end();
    });

    // 6th attempt is blocked with 429
    await new Promise<void>((resolve, reject) => {
      const payload = JSON.stringify({ pairingSecret: 'invalid_secret' });
      const req = http.request({
        host: '127.0.0.1',
        port: remotePort,
        path: '/api/remote/pair',
        method: 'POST',
        headers: {
          Host: tunnelHost,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
        },
      }, (res) => {
        assert.strictEqual(res.statusCode, 429);
        res.resume();
        res.on('end', () => resolve());
      });
      req.on('error', reject);
      req.write(payload);
      req.end();
    });

    // 4. Generate new pairing and pair successfully
    // Clear locked IP for legitimate test pair
    const pairing = remoteManager.generatePairing(60000);
    // Use authManager pair directly to bypass same-IP lockout in test
    const pairResult = authManager.pair(pairing.secret, 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4)', '198.51.100.88', 'view');

    assert.ok(pairResult.deviceId);
    assert.ok(pairResult.deviceToken.startsWith('rem_dev_'));
    const phoneToken = pairResult.deviceToken;
    const phoneDeviceId = pairResult.deviceId;

    // 5. Connect WebSocket from phone over the dedicated remote listener
    const ws = new WebSocket(`ws://127.0.0.1:${remotePort}`, {
      headers: {
        Origin: `https://${tunnelHost}`,
        Host: tunnelHost,
      },
    });

    await new Promise<void>((resolve, reject) => {
      ws.on('open', () => {
        ws.send(JSON.stringify({
          protocol: 1,
          kind: 'hello',
          id: 'hl_phone_1',
          ts: Date.now(),
          type: 'connection.hello',
          payload: {
            token: phoneToken,
            client: { name: 'mobile_safari', version: '1.3', platform: 'ios' },
            encoding: 'json',
            capabilities: ['replay.v1', 'workspace.v1'],
          },
        }));
      });

      ws.on('message', (raw) => {
        const msg = JSON.parse(raw.toString());
        if (msg.kind === 'welcome') {
          resolve();
        }
      });

      ws.on('error', reject);
    });

    // 6. Verify phone connection is active and flagged as remote
    const remoteConn = manager.getAll().find(c => c.deviceId === phoneDeviceId);
    assert.ok(remoteConn);
    assert.strictEqual(remoteConn?.isRemote, true);

    // 7. Test guardrail: remote connection in view mode cannot modify files or execute remote.*
    const blockedWritePromise = new Promise<any>((resolve) => {
      const listener = (raw: WebSocket.RawData) => {
        const msg = JSON.parse(raw.toString());
        if (msg.kind === 'result' && msg.commandId === 'c_phone_blocked') {
          ws.off('message', listener);
          resolve(msg);
        }
      };
      ws.on('message', listener);

      ws.send(JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'cmd_b1',
        ts: Date.now(),
        commandId: 'c_phone_blocked',
        type: 'workspace.saveFile',
        payload: { path: 'test.txt', content: 'test', revision: '0'.repeat(64) },
      }));
    });

    const blockedResult = await blockedWritePromise;
    assert.strictEqual(blockedResult.payload.state, 'rejected');

    // 8. Remote connection cannot execute remote.* or daemon.setConfig
    const blockedRemoteCmdPromise = new Promise<any>((resolve) => {
      const listener = (raw: WebSocket.RawData) => {
        const msg = JSON.parse(raw.toString());
        if (msg.kind === 'result' && msg.commandId === 'c_phone_rem_cmd') {
          ws.off('message', listener);
          resolve(msg);
        }
      };
      ws.on('message', listener);

      ws.send(JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'cmd_b2',
        ts: Date.now(),
        commandId: 'c_phone_rem_cmd',
        type: 'remote.stop',
        payload: {},
      }));
    });

    const blockedRemoteResult = await blockedRemoteCmdPromise;
    assert.strictEqual(blockedRemoteResult.payload.state, 'rejected');

    // 9. Revoke device from desktop -> phone socket must immediately disconnect with 4003
    const disconnectPromise = new Promise<{ code: number; reason: string }>((resolve) => {
      ws.on('close', (code, reason) => {
        resolve({ code, reason: reason.toString() });
      });
    });

    remoteManager.revokeDevice(phoneDeviceId);
    const closeInfo = await disconnectPromise;
    assert.strictEqual(closeInfo.code, 4003);
    assert.ok(closeInfo.reason.includes('Device Revoked'));

    // 10. After revocation, attempting to bootstrap with the revoked token fails
    const postRevokeRes = await new Promise<any>((resolve, reject) => {
      const req = http.request({
        host: '127.0.0.1',
        port: remotePort,
        path: '/api/session-bootstrap',
        headers: {
          Host: tunnelHost,
          Authorization: `Bearer ${phoneToken}`,
        },
      }, (res) => {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => resolve({ status: res.statusCode, data: JSON.parse(body) }));
      });
      req.on('error', reject);
      req.end();
    });

    assert.strictEqual(postRevokeRes.status, 401);
    assert.strictEqual(postRevokeRes.data.needsPairing, true);

  } finally {
    await remoteManager.stop().catch(() => {});
    wss.close();
    httpServer.close();
    remoteHttpServer.close();
    try { fs.unlinkSync(tmpDevices); } catch {}
  }
});
