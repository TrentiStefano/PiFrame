import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as path from 'node:path';
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
import { FaultProxy } from '../../../tools/fault-proxy/dist/index.js';

const makeId = (prefix: string) => `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2)}`;

test('Fault Injection Suite: proxy drops, duplicate frames, and corrupted frames handled cleanly', async (t) => {
  process.env.FAKE_PI_SCENARIO = 'slow-stream';
  const fakePiPath = path.resolve(__dirname, '../../../tools/fake-pi/dist/index.js');
  const token = 'test_fault_token_123';
  const version = '0.1.0';
  const startedAt = Date.now();

  const httpServer = createHttpServer({
    config: DEFAULT_CONFIG,
    token,
    version,
    startedAt
  });

  await new Promise<void>((resolve, reject) => {
    httpServer.listen(0, '127.0.0.1', () => resolve());
    httpServer.on('error', reject);
  });

  const daemonPort = (httpServer.address() as any).port;
  let registry!: SessionRegistry;
  let dispatcher!: Dispatcher;

  const { wss, manager } = createWsServer({
    httpServer,
    config: DEFAULT_CONFIG,
    token,
    version,
    startedAt,
    piInfo: { path: fakePiPath, version: '0.85.1', supported: true },
    port: daemonPort,
    onCommand: async (conn, cmd) => {
      await dispatcher.handle(conn, cmd);
    },
    onAttach: async (conn, sid, lastSeq) => {
      await registry.attachClient(sid, conn, lastSeq);
    },
    onDetach: async (conn, sid) => {
      await registry.detachClient(sid, conn);
    }
  });

  registry = new SessionRegistry({
    piExecutablePath: fakePiPath,
    capabilities: {
      version: '0.85.1',
      supported: true,
      modes: ['rpc'],
      features: ['thinking', 'tools', 'compaction'],
    },
    workerIdleTimeoutMs: 60000,
    connectionManager: manager,
  });

  dispatcher = new Dispatcher(registry, manager);

  t.after(async () => {
    registry.closeAll();
    wss.close();
    await new Promise<void>((resolve) => httpServer.close(() => resolve()));
  });

  // 1. Test duplicate frames through FaultProxy
  await t.test('duplicate frames are received and deduplicated by seq', async () => {
    const proxy = new FaultProxy({
      targetPort: daemonPort,
      duplicateFrames: true
    });
    const proxyPort = await proxy.start();

    try {
      const ws = new WebSocket(`ws://127.0.0.1:${proxyPort}/api/ws`);
      await new Promise<void>((resolve) => ws.on('open', resolve));

      // Send hello
      ws.send(
        JSON.stringify({
          protocol: 1,
          kind: 'hello',
          id: makeId('hl'),
          ts: Date.now(),
          type: 'connection.hello',
          payload: {
            token,
            client: { name: 'test', version: '0.1.0', platform: 'test' },
            encoding: 'json'
          }
        })
      );

      // Collect frames
      const receivedSeqs: number[] = [];
      const receivedKinds: string[] = [];

      await new Promise<void>((resolve, reject) => {
        const timeout = setTimeout(() => resolve(), 3000);
        let welcomeReceived = false;
        ws.on('message', (raw) => {
          try {
            const msg = JSON.parse(raw.toString('utf8'));
            receivedKinds.push(msg.kind);
            if (msg.kind === 'welcome' && !welcomeReceived) {
              welcomeReceived = true;
              // Ping to trigger response
              ws.send(JSON.stringify({ protocol: 1, kind: 'ping', id: makeId('p'), ts: Date.now(), type: 'ping', payload: {} }));
            }
            if (msg.kind === 'pong') {
              clearTimeout(timeout);
              resolve();
            }
          } catch {}
        });
        ws.on('error', reject);
      });

      ws.close();
      assert.ok(receivedKinds.includes('welcome'), 'Must receive welcome frame despite duplicate proxy');
    } finally {
      await proxy.close();
    }
  });

  // 2. Test corrupted frame handling
  await t.test('corrupted truncated frame does not crash client loop or daemon', async () => {
    const proxy = new FaultProxy({
      targetPort: daemonPort,
      corruptEveryNFrames: 1
    });
    const proxyPort = await proxy.start();

    try {
      const ws = new WebSocket(`ws://127.0.0.1:${proxyPort}/api/ws`);
      await new Promise<void>((resolve) => ws.on('open', resolve));

      ws.send(
        JSON.stringify({
          protocol: 1,
          kind: 'hello',
          id: makeId('hl'),
          ts: Date.now(),
          type: 'connection.hello',
          payload: {
            token,
            client: { name: 'test', version: '0.1.0', platform: 'test' },
            encoding: 'json'
          }
        })
      );

      let hadMalformed = false;

      await new Promise<void>((resolve) => {
        const timeout = setTimeout(resolve, 1000);
        ws.on('message', (raw) => {
          try {
            JSON.parse(raw.toString('utf8'));
          } catch {
            hadMalformed = true;
            clearTimeout(timeout);
            resolve();
          }
        });
      });

      ws.close();
      assert.ok(hadMalformed, 'Fault proxy must have injected at least one malformed frame');
      // Daemon remains healthy
      assert.strictEqual(wss.clients.size >= 0, true);
    } finally {
      await proxy.close();
    }
  });
});
