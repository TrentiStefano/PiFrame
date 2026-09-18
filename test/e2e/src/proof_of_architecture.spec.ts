import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import WebSocket from 'ws';

const makeId = (prefix: string) => `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2)}`;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Import agentd components
import { createHttpServer } from '../../../apps/agentd/dist/server/httpServer.js';
import { createWsServer } from '../../../apps/agentd/dist/server/wsServer.js';
import { SessionRegistry } from '../../../apps/agentd/dist/sessions/SessionRegistry.js';
import { Dispatcher } from '../../../apps/agentd/dist/commands/Dispatcher.js';
import { DEFAULT_CONFIG } from '../../../apps/agentd/dist/config/config.js';

test('M1 Proof of Architecture: GUI disconnect does not abort agent execution; client re-attaches and catches up', async () => {
  // 1. Configure environment to use fake-pi in slow-stream mode
  process.env.FAKE_PI_SCENARIO = 'slow-stream';
  const fakePiPath = path.resolve(__dirname, '../../../tools/fake-pi/dist/index.js');

  const token = 'test_secret_token_proof_of_arch';
  const version = '0.1.0';
  const startedAt = Date.now();

  const httpServer = createHttpServer({
    config: DEFAULT_CONFIG,
    token,
    version,
    startedAt,
  });

  await new Promise<void>((resolve, reject) => {
    httpServer.listen(0, '127.0.0.1', () => resolve());
    httpServer.on('error', reject);
  });

  const boundAddr = httpServer.address() as any;
  const port = boundAddr.port;

  let registry!: SessionRegistry;
  let dispatcher!: Dispatcher;

  const { wss, manager } = createWsServer({
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
    },
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

  // ---------------------------------------------------------------------------
  // 2. Client 1 connects, creates session, attaches, and starts prompt
  // ---------------------------------------------------------------------------
  const ws1 = new WebSocket(`ws://127.0.0.1:${port}`);
  await new Promise((resolve) => ws1.on('open', resolve));

  const send1 = (msg: any) => ws1.send(JSON.stringify(msg));

  // Handshake
  send1({
    protocol: 1,
    kind: 'hello',
    id: makeId('hl'),
    ts: Date.now(),
    type: 'connection.hello',
    payload: {
      token,
      client: { name: 'client-1', version: '1.0.0', platform: 'test' },
      encoding: 'json',
      capabilities: ['replay.v1'],
    },
  });

  // Wait for welcome
  await new Promise<void>((resolve) => {
    const handler = (data: any) => {
      const parsed = JSON.parse(data.toString());
      if (parsed.kind === 'welcome') {
        ws1.off('message', handler);
        resolve();
      }
    };
    ws1.on('message', handler);
  });

  // Create session
  const session = await registry.createSession({ name: 'Architecture Proof Session' });
  const sessionId = session.id;

  // Client 1 attaches to session
  send1({
    protocol: 1,
    kind: 'command',
    id: makeId('cmd'),
    ts: Date.now(),
    sessionId,
    commandId: makeId('att'),
    type: 'session.attach',
    payload: {},
  });

  // Client 1 initiates prompt
  send1({
    protocol: 1,
    kind: 'command',
    id: makeId('cmd'),
    ts: Date.now(),
    sessionId,
    commandId: makeId('prm'),
    type: 'agent.prompt',
    payload: { text: 'Stream me a slow message' },
  });

  const client1Events: any[] = [];
  let disconnectSeq = 0;

  // Listen for events until 3 text.delta events arrive
  await new Promise<void>((resolve) => {
    ws1.on('message', (data: any) => {
      const msg = JSON.parse(data.toString());
      if (msg.kind === 'event') {
        client1Events.push(msg);
        if (msg.type === 'text.delta') {
          const textDeltas = client1Events.filter((e) => e.type === 'text.delta');
          if (textDeltas.length === 3) {
            disconnectSeq = msg.seq;
            resolve();
          }
        }
      }
    });
  });

  assert.ok(disconnectSeq >= 3, `Expected disconnectSeq >= 3, got ${disconnectSeq}`);
  console.log(`[E2E] Client 1 received 3 text.delta events up to seq=${disconnectSeq}. Terminating connection abruptly...`);

  // ---------------------------------------------------------------------------
  // 3. Abrupt disconnect of Client 1 (GUI crash simulation)
  // ---------------------------------------------------------------------------
  ws1.terminate(); // Closes TCP socket abruptly without PCP detach/abort

  // Verify that the worker process in the daemon is still alive and actively executing
  const liveSession = registry.getSession(sessionId);
  assert.ok(liveSession, 'Session must still exist in daemon');
  assert.ok(liveSession.worker, 'Worker must still exist in session');
  assert.equal(liveSession.worker.health().alive, true, 'Worker must be alive despite GUI disconnect');

  // Wait 1.5 seconds while Pi continues streaming in background
  console.log('[E2E] Waiting 1.5s while Pi continues background streaming into journal...');
  await new Promise((r) => setTimeout(r, 1500));

  // Verify journal has accumulated events beyond Client 1's disconnect point
  assert.ok(
    liveSession.journal.currentSeq > disconnectSeq,
    `Journal currentSeq (${liveSession.journal.currentSeq}) should exceed disconnectSeq (${disconnectSeq})`
  );

  // ---------------------------------------------------------------------------
  // 4. Client 2 connects (GUI re-opened / re-attached) with lastSeq
  // ---------------------------------------------------------------------------
  console.log(`[E2E] Client 2 connecting and attaching with lastSeq=${disconnectSeq}...`);
  const ws2 = new WebSocket(`ws://127.0.0.1:${port}`);
  await new Promise((resolve) => ws2.on('open', resolve));

  const send2 = (msg: any) => ws2.send(JSON.stringify(msg));

  // Client 2 handshake
  send2({
    protocol: 1,
    kind: 'hello',
    id: makeId('hl'),
    ts: Date.now(),
    type: 'connection.hello',
    payload: {
      token,
      client: { name: 'client-2', version: '1.0.0', platform: 'test' },
      encoding: 'json',
      capabilities: ['replay.v1'],
    },
  });

  await new Promise<void>((resolve) => {
    const handler = (data: any) => {
      const parsed = JSON.parse(data.toString());
      if (parsed.kind === 'welcome') {
        ws2.off('message', handler);
        resolve();
      }
    };
    ws2.on('message', handler);
  });

  // Client 2 attaches with lastSeq
  send2({
    protocol: 1,
    kind: 'command',
    id: makeId('cmd'),
    ts: Date.now(),
    sessionId,
    commandId: makeId('att2'),
    type: 'session.attach',
    payload: { lastSeq: disconnectSeq },
  });

  const client2Events: any[] = [];

  // Collect until run.settled
  await new Promise<void>((resolve) => {
    ws2.on('message', (data: any) => {
      const msg = JSON.parse(data.toString());
      if (msg.kind === 'event') {
        client2Events.push(msg);
        if (msg.type === 'run.settled') {
          resolve();
        }
      }
    });
  });

  console.log(`[E2E] Client 2 received ${client2Events.length} events starting from seq=${client2Events[0]?.seq} to run.settled`);

  // Verify continuity
  assert.ok(client2Events.length > 0);
  assert.equal(client2Events[0].seq, disconnectSeq + 1, 'First event replayed to Client 2 must immediately follow disconnectSeq');

  // Verify all seqs are strictly sequential
  for (let i = 1; i < client2Events.length; i++) {
    assert.equal(
      client2Events[i].seq,
      client2Events[i - 1].seq + 1,
      `Events must be strictly sequential (expected ${client2Events[i - 1].seq + 1}, got ${client2Events[i].seq})`
    );
  }

  // Verify completion
  assert.ok(client2Events.some((e) => e.type === 'message.completed'), 'Must receive message.completed');
  assert.ok(client2Events.some((e) => e.type === 'run.settled'), 'Must receive run.settled');

  // Cleanup
  ws2.close();
  await registry.closeAll(1000);
  await new Promise<void>((resolve) => httpServer.close(() => resolve()));
  delete process.env.FAKE_PI_SCENARIO;

  console.log('[E2E] PROOF OF ARCHITECTURE VERIFIED: Disconnecting GUI leaves Pi active and streaming, reconnect replays flawlessly!');
});
