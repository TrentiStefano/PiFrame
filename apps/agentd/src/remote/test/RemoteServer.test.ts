import { test } from 'node:test';
import * as assert from 'node:assert';
import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { WebSocket } from 'ws';
import { createHttpServer } from '../../server/httpServer.js';
import { createWsServer } from '../../server/wsServer.js';
import { RemoteManager } from '../RemoteManager.js';
import { RemoteAuthManager } from '../RemoteAuthManager.js';
import { DEFAULT_CONFIG } from '../../config/config.js';

test('RemoteServer: two-listener architecture (local loopback vs dedicated remote listener)', async () => {
  const tmpDevices = path.join(os.tmpdir(), `pi_test_server_dev_${Date.now()}.json`);
  const authManager = new RemoteAuthManager(tmpDevices);
  const remoteManager = new RemoteManager(DEFAULT_CONFIG, authManager);

  const masterToken = 'test_master_token_256bit_local_only';
  let localPort = 0;
  let remotePort = 0;

  // 1. Local listener
  const localServer = createHttpServer({
    config: DEFAULT_CONFIG,
    token: masterToken,
    version: '1.3.0',
    startedAt: Date.now(),
    remoteManager,
    listener: 'local'
  });

  await new Promise<void>((resolve) => {
    localServer.listen(0, '127.0.0.1', () => {
      localPort = (localServer.address() as any).port;
      resolve();
    });
  });

  // 2. Remote listener
  const remoteServer = createHttpServer({
    config: DEFAULT_CONFIG,
    token: masterToken,
    version: '1.3.0',
    startedAt: Date.now(),
    remoteManager,
    listener: 'remote'
  });

  await new Promise<void>((resolve) => {
    remoteServer.listen(0, '127.0.0.1', () => {
      remotePort = (remoteServer.address() as any).port;
      remoteManager.setListenerPort(remotePort);
      resolve();
    });
  });

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

  try {
    // 1. Direct local request to /api/session-bootstrap gets master token
    const localRes = await new Promise<any>((resolve, reject) => {
      http.get(`http://127.0.0.1:${localPort}/api/session-bootstrap`, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve({ status: res.statusCode, data: JSON.parse(data), headers: res.headers }));
      }).on('error', reject);
    });
    assert.strictEqual(localRes.status, 200);
    assert.strictEqual(localRes.data.token, masterToken);
    assert.strictEqual(localRes.data.mode, 'local');

    // 2. Local listener strictly rejects proxy headers (H2 defense)
    const proxyOnLocal = await new Promise<number>((resolve, reject) => {
      const req = http.request({
        host: '127.0.0.1',
        port: localPort,
        path: '/api/session-bootstrap',
        headers: {
          Host: `127.0.0.1:${localPort}`,
          'X-Forwarded-For': '198.51.100.1'
        }
      }, (res) => resolve(res.statusCode || 0));
      req.on('error', reject);
      req.end();
    });
    assert.strictEqual(proxyOnLocal, 403);

    // 3. Start remote tunnel in Custom mode
    const testTunnelHost = 'remote-test-tunnel.example.com';
    const testTunnelUrl = `https://${testTunnelHost}`;
    await remoteManager.start({
      tunnelProvider: 'custom',
      customUrl: testTunnelUrl
    });

    assert.strictEqual(remoteManager.isRemoteHostAllowed(testTunnelHost), true);
    assert.strictEqual(remoteManager.isRemoteHostAllowed('malicious-site.com'), false);

    // 4. Remote listener request without auth returns 401 needsPairing
    const remoteUnauth = await new Promise<any>((resolve, reject) => {
      const req = http.request({
        host: '127.0.0.1',
        port: remotePort,
        path: '/api/session-bootstrap',
        headers: {
          Host: testTunnelHost
        }
      }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve({ status: res.statusCode, data: JSON.parse(data) }));
      });
      req.on('error', reject);
      req.end();
    });
    assert.strictEqual(remoteUnauth.status, 401);
    assert.strictEqual(remoteUnauth.data.needsPairing, true);

    // 5. Remote listener NEVER accepts master token
    const masterOnRemote = await new Promise<any>((resolve, reject) => {
      const req = http.request({
        host: '127.0.0.1',
        port: remotePort,
        path: '/api/session-bootstrap',
        headers: {
          Host: testTunnelHost,
          Authorization: `Bearer ${masterToken}`
        }
      }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve({ status: res.statusCode, data: JSON.parse(data) }));
      });
      req.on('error', reject);
      req.end();
    });
    assert.strictEqual(masterOnRemote.status, 401);

    // 6. Pairing via POST /api/remote/pair with pairingSecret
    const pairing = remoteManager.generatePairing(60000);
    assert.ok(pairing.secret);

    const pairRes = await new Promise<any>((resolve, reject) => {
      const payload = JSON.stringify({ pairingSecret: pairing.secret });
      const req = http.request({
        host: '127.0.0.1',
        port: remotePort,
        path: '/api/remote/pair',
        method: 'POST',
        headers: {
          Host: testTunnelHost,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
          'User-Agent': 'Mozilla/5.0 (iPhone; iOS 17)'
        }
      }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve({
          status: res.statusCode,
          data: JSON.parse(data),
          cookie: res.headers['set-cookie']
        }));
      });
      req.on('error', reject);
      req.write(payload);
      req.end();
    });

    assert.strictEqual(pairRes.status, 200);
    assert.strictEqual(pairRes.data.ok, true);
    const deviceToken = pairRes.data.deviceToken;
    const deviceId = pairRes.data.deviceId;
    assert.ok(deviceToken.startsWith('rem_dev_'));
    assert.ok(pairRes.cookie?.[0]?.includes('pcp_device_token='));
    assert.ok(pairRes.cookie?.[0]?.includes('Secure'));

    // 7. WebSocket connect over remote listener with device token
    const ws = new WebSocket(`ws://127.0.0.1:${remotePort}`, {
      headers: {
        Origin: `https://${testTunnelHost}`,
        Host: testTunnelHost
      }
    });

    await new Promise<void>((resolve, reject) => {
      ws.on('open', () => {
        ws.send(JSON.stringify({
          protocol: 1,
          kind: 'hello',
          id: 'hl_test',
          ts: Date.now(),
          type: 'connection.hello',
          payload: {
            token: deviceToken,
            client: { name: 'phone_web', version: '1.0', platform: 'ios' },
            encoding: 'json',
            capabilities: []
          }
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

    // Check connection is flagged as remote in manager
    const conns = manager.getAll();
    const remoteConn = conns.find(c => c.deviceId === deviceId);
    assert.ok(remoteConn);
    assert.strictEqual(remoteConn?.isRemote, true);

    // 8. WebSocket on remote listener with master token is REJECTED with 4003
    const wsMaster = new WebSocket(`ws://127.0.0.1:${remotePort}`, {
      headers: {
        Origin: `https://${testTunnelHost}`,
        Host: testTunnelHost
      }
    });

    const masterClosePromise = new Promise<number>((resolve) => {
      wsMaster.on('close', (code) => resolve(code));
    });

    wsMaster.on('open', () => {
      wsMaster.send(JSON.stringify({
        protocol: 1,
        kind: 'hello',
        id: 'hl_master',
        ts: Date.now(),
        type: 'connection.hello',
        payload: {
          token: masterToken,
          client: { name: 'attacker', version: '1.0' },
          encoding: 'json',
          capabilities: []
        }
      }));
    });

    const masterCloseCode = await masterClosePromise;
    assert.strictEqual(masterCloseCode, 4003);

    // 9. Revoke device -> active connection is immediately closed with 4003
    const closedPromise = new Promise<{ code: number; reason: string }>((resolve) => {
      ws.on('close', (code, reason) => {
        resolve({ code, reason: reason.toString() });
      });
    });

    remoteManager.revokeDevice(deviceId);
    const closeInfo = await closedPromise;
    assert.strictEqual(closeInfo.code, 4003);
    assert.ok(closeInfo.reason.includes('Device Revoked'));

  } finally {
    await remoteManager.stop().catch(() => {});
    wss.close();
    localServer.close();
    remoteServer.close();
    try { fs.unlinkSync(tmpDevices); } catch {}
  }
});
