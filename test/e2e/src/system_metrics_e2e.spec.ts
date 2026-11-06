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

test('E2E: System Metrics - Subscribe over real WS, receive events, unsubscribe cleanly', async () => {
  const fakePiPath = path.resolve(__dirname, '../../../tools/fake-pi/dist/index.js');
  const token = 'test_token_metrics_e2e_secret';
  const version = '1.3.0';
  const startedAt = Date.now();

  const httpServer = createHttpServer({
    config: DEFAULT_CONFIG,
    token,
    version,
    startedAt,
    listener: 'local'
  });

  await new Promise<void>((resolve, reject) => {
    httpServer.listen(0, '127.0.0.1', () => resolve());
    httpServer.on('error', reject);
  });

  const port = (httpServer.address() as any).port;

  let registry!: SessionRegistry;
  let dispatcher!: Dispatcher;

  const { wss: _wss, manager } = createWsServer({
    httpServer,
    config: DEFAULT_CONFIG,
    token,
    version,
    startedAt,
    piInfo: { path: fakePiPath, version: '0.85.1', supported: true },
    port,
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
    capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 60000,
    connectionManager: manager
  });

  dispatcher = new Dispatcher(registry, manager);

  const client = new WebSocket(`ws://127.0.0.1:${port}/api/ws`);
  await new Promise<void>((resolve, reject) => {
    client.on('open', resolve);
    client.on('error', reject);
  });

  const receivedMessages: any[] = [];
  client.on('message', (data) => {
    try {
      receivedMessages.push(JSON.parse(data.toString()));
    } catch {}
  });

  try {
    // 1. Send hello
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'hello',
        id: 'msg_hello_1',
        ts: Date.now(),
        type: 'connection.hello',
        payload: {
          token,
          client: { name: 'e2e-test', version: '1.0.0', platform: 'test' },
          encoding: 'json',
          capabilities: ['replay.v1']
        }
      })
    );

    // Wait for welcome
    const welcome = await new Promise<any>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timed out waiting for welcome')), 3000);
      const interval = setInterval(() => {
        const found = receivedMessages.find((m) => m.kind === 'welcome');
        if (found) {
          clearTimeout(timeout);
          clearInterval(interval);
          resolve(found);
        }
      }, 50);
    });

    assert.equal(welcome.kind, 'welcome');
    assert.ok(
      welcome.payload.capabilities.includes('system.metrics.v1'),
      'Welcome capabilities should include system.metrics.v1'
    );

    // 2. Send system.metrics.subscribe
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'msg_cmd_sub',
        ts: Date.now(),
        commandId: 'cmd_sub_e2e_001',
        sessionId: '@daemon',
        type: 'system.metrics.subscribe',
        payload: {}
      })
    );

    // Wait for result
    const subResult = await new Promise<any>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timed out waiting for subscribe result')), 3000);
      const interval = setInterval(() => {
        const found = receivedMessages.find((m) => m.kind === 'result' && m.commandId === 'cmd_sub_e2e_001');
        if (found) {
          clearTimeout(timeout);
          clearInterval(interval);
          resolve(found);
        }
      }, 50);
    });

    assert.equal(subResult.payload.state, 'completed');
    assert.equal(subResult.payload.data.intervalMs, 1000);

    // 3. Wait for >= 1 system.metrics event within ~3s
    const metricsEvent = await new Promise<any>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timed out waiting for system.metrics event')), 4000);
      const interval = setInterval(() => {
        const found = receivedMessages.find((m) => m.kind === 'event' && m.type === 'system.metrics');
        if (found) {
          clearTimeout(timeout);
          clearInterval(interval);
          resolve(found);
        }
      }, 50);
    });

    assert.equal(metricsEvent.kind, 'event');
    assert.equal(metricsEvent.type, 'system.metrics');
    assert.equal(metricsEvent.sessionId, '@daemon');
    assert.equal(metricsEvent.seq, 0);
    assert.ok(typeof metricsEvent.payload.sampledAt === 'number');
    assert.ok('cpu' in metricsEvent.payload);
    assert.ok('memory' in metricsEvent.payload);
    assert.ok('disk' in metricsEvent.payload);
    assert.ok('gpu' in metricsEvent.payload);
    assert.ok('source' in metricsEvent.payload.gpu);

    // 4. Send system.metrics.unsubscribe
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'msg_cmd_unsub',
        ts: Date.now(),
        commandId: 'cmd_unsub_e2e_001',
        sessionId: '@daemon',
        type: 'system.metrics.unsubscribe',
        payload: {}
      })
    );

    const unsubResult = await new Promise<any>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timed out waiting for unsubscribe result')), 3000);
      const interval = setInterval(() => {
        const found = receivedMessages.find((m) => m.kind === 'result' && m.commandId === 'cmd_unsub_e2e_001');
        if (found) {
          clearTimeout(timeout);
          clearInterval(interval);
          resolve(found);
        }
      }, 50);
    });

    assert.equal(unsubResult.payload.state, 'completed');

    // 5. Verify no more system.metrics events arrive after unsubscribe
    const countBefore = receivedMessages.filter((m) => m.type === 'system.metrics').length;
    await new Promise((resolve) => setTimeout(resolve, 1500));
    const countAfter = receivedMessages.filter((m) => m.type === 'system.metrics').length;
    assert.equal(countAfter, countBefore, 'No additional system.metrics events should arrive after unsubscribe');
  } finally {
    dispatcher.dispose();
    client.close();
    await new Promise<void>((resolve) => httpServer.close(() => resolve()));
  }
});
