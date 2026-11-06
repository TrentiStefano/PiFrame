import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import WebSocket from 'ws';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

import { createHttpServer } from '../../../apps/agentd/dist/server/httpServer.js';
import { createWsServer } from '../../../apps/agentd/dist/server/wsServer.js';
import { SessionRegistry } from '../../../apps/agentd/dist/sessions/SessionRegistry.js';
import { Dispatcher } from '../../../apps/agentd/dist/commands/Dispatcher.js';
import { DEFAULT_CONFIG } from '../../../apps/agentd/dist/config/config.js';

test('E2E: Side Conversation - Open, stream reply, isolate main, close with fake-pi', async () => {
  const fakePiPath = path.resolve(__dirname, '../../../tools/fake-pi/dist/index.js');
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-e2e-side-'));
  const token = 'test_token_side_e2e_secret';
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
    onAttach: async (conn, sid, lastSeq, commandId) => {
      if (sid.startsWith('side_') || dispatcher.getSideManager().hasStream(sid)) {
        await dispatcher.getSideManager().handleAttach(sid, conn, lastSeq, commandId);
      } else {
        await registry.attachClient(sid, conn, lastSeq, commandId);
      }
    },
    onDetach: async (conn, sid) => {
      if (sid.startsWith('side_') || dispatcher.getSideManager().hasStream(sid)) {
        dispatcher.getSideManager().handleDetach(sid, conn);
      } else {
        await registry.detachClient(sid, conn);
      }
    }
  });

  registry = new SessionRegistry({
    piExecutablePath: fakePiPath,
    capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: ['tools'] },
    workerIdleTimeoutMs: 60000,
    connectionManager: manager
  });

  dispatcher = new Dispatcher(registry, manager);

  const client = new WebSocket(`ws://127.0.0.1:${port}/api/ws`);
  let client2: WebSocket | null = null;
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

  const waitFor = async (predicate: (msg: any) => boolean, timeoutMs = 8000, desc = 'message') => {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const match = receivedMessages.find(predicate);
      if (match) return match;
      await new Promise((r) => setTimeout(r, 50));
    }
    throw new Error(`Timed out waiting for ${desc}`);
  };

  try {
    // 1. Send hello
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'hello',
        id: 'msg_hello',
        ts: Date.now(),
        type: 'connection.hello',
        payload: {
          token,
          client: { name: 'e2e-side-test', version: '1.0.0', platform: 'test' },
          encoding: 'json',
          capabilities: ['replay.v1']
        }
      })
    );

    const welcome = await waitFor((m) => m.kind === 'welcome', 3000, 'welcome frame');
    assert.equal(welcome.kind, 'welcome');

    // 2. Create main session
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'msg_cmd_create',
        ts: Date.now(),
        commandId: 'cmd_create_main',
        type: 'session.create',
        payload: { cwd: tempDir, name: 'Main E2E Session' }
      })
    );

    const createRes = await waitFor(
      (m) => m.kind === 'result' && m.commandId === 'cmd_create_main',
      4000,
      'session.create result'
    );
    assert.equal(createRes.payload.state, 'completed');
    const mainSessionId = createRes.payload.data.session.id;
    assert.ok(mainSessionId);

    // 3. Attach to main session
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'msg_cmd_att',
        ts: Date.now(),
        commandId: 'cmd_att_main',
        sessionId: mainSessionId,
        type: 'session.attach',
        payload: { lastSeq: null }
      })
    );

    await waitFor(
      (m) => m.kind === 'snapshot' && m.sessionId === mainSessionId,
      3000,
      'snapshot for main session'
    );

    // 4. Send prompt to main session
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'msg_cmd_prompt_main',
        ts: Date.now(),
        commandId: 'cmd_prompt_main',
        sessionId: mainSessionId,
        type: 'agent.prompt',
        payload: { text: 'Hello main agent' }
      })
    );

    // Wait for main session run.settled
    await waitFor(
      (m) => m.kind === 'event' && m.sessionId === mainSessionId && m.type === 'run.settled',
      8000,
      'run.settled on main session'
    );

    const mainSessionEventsBeforeSide = receivedMessages.filter(
      (m) => m.kind === 'event' && m.sessionId === mainSessionId
    );
    const mainEventCountBefore = mainSessionEventsBeforeSide.length;
    assert.ok(mainEventCountBefore > 0);

    // 5. Open side conversation with question (using Dart helper envelope shape: sessionId = mainSessionId)
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'msg_cmd_side_open',
        ts: Date.now(),
        commandId: 'cmd_side_open_1',
        sessionId: mainSessionId,
        type: 'side.open',
        payload: {
          sessionId: mainSessionId,
          question: 'What did the main session discuss?'
        }
      })
    );

    const openResult = await waitFor(
      (m) => m.kind === 'result' && m.commandId === 'cmd_side_open_1',
      5000,
      'side.open result'
    );
    assert.equal(openResult.payload.state, 'completed');
    const { sideId, streamId } = openResult.payload.data;
    assert.ok(sideId.startsWith('side_'));
    assert.equal(streamId, sideId);

    // 6. Verify side.opened event received on streamId
    const sideOpenedEvt = await waitFor(
      (m) => m.kind === 'event' && m.sessionId === streamId && m.type === 'side.opened',
      4000,
      'side.opened event'
    );
    assert.equal(sideOpenedEvt.payload.sideId, sideId);
    assert.equal(sideOpenedEvt.payload.parentSessionId, mainSessionId);

    // 7. Verify streamed reply from side conversation worker
    const sideTextDelta = await waitFor(
      (m) => m.kind === 'event' && m.sessionId === streamId && m.type === 'text.delta',
      5000,
      'text.delta on side stream'
    );
    assert.ok(sideTextDelta.payload.delta);

    await waitFor(
      (m) => m.kind === 'event' && m.sessionId === streamId && m.type === 'run.settled',
      5000,
      'run.settled on side stream'
    );

    // 8. Send side.prompt with Dart helper envelope shape (sessionId = sideId)
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'msg_cmd_side_prompt',
        ts: Date.now(),
        commandId: 'cmd_side_prompt_1',
        sessionId: sideId,
        type: 'side.prompt',
        payload: {
          sideId,
          text: 'Can you summarize the main points?'
        }
      })
    );

    const promptResult = await waitFor(
      (m) => m.kind === 'result' && m.commandId === 'cmd_side_prompt_1',
      5000,
      'side.prompt result'
    );
    assert.equal(promptResult.payload.state, 'completed');
    assert.equal(promptResult.payload.data.prompted, true);

    await waitFor(
      (m) => m.kind === 'event' && m.sessionId === streamId && m.type === 'run.settled',
      5000,
      'run.settled on side stream after prompt'
    );

    // 9. Send side.abort with Dart helper envelope shape (sessionId = sideId)
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'msg_cmd_side_abort',
        ts: Date.now(),
        commandId: 'cmd_side_abort_1',
        sessionId: sideId,
        type: 'side.abort',
        payload: {
          sideId
        }
      })
    );

    const abortResult = await waitFor(
      (m) => m.kind === 'result' && m.commandId === 'cmd_side_abort_1',
      5000,
      'side.abort result'
    );
    assert.equal(abortResult.payload.state, 'completed');
    assert.equal(abortResult.payload.data.aborted, true);

    // 10. Verify main session events were completely unaffected
    const mainSessionEventsAfterSide = receivedMessages.filter(
      (m) => m.kind === 'event' && m.sessionId === mainSessionId
    );
    assert.equal(
      mainSessionEventsAfterSide.length,
      mainEventCountBefore,
      'Main session must receive NO events while side conversation runs'
    );

    // 10b. Verify session.attach on side stream yields exactly one replay of buffered events (no duplicate seq)
    client2 = new WebSocket(`ws://127.0.0.1:${port}/api/ws`);
    await new Promise<void>((resolve, reject) => {
      client2!.on('open', resolve);
      client2!.on('error', reject);
    });

    const client2Messages: any[] = [];
    client2.on('message', (data) => {
      try {
        client2Messages.push(JSON.parse(data.toString()));
      } catch {}
    });

    const waitForClient2 = async (predicate: (msg: any) => boolean, timeoutMs = 5000, desc = 'client2 message') => {
      const start = Date.now();
      while (Date.now() - start < timeoutMs) {
        const match = client2Messages.find(predicate);
        if (match) return match;
        await new Promise((r) => setTimeout(r, 50));
      }
      throw new Error(`Timed out waiting for ${desc}`);
    };

    client2.send(
      JSON.stringify({
        protocol: 1,
        kind: 'hello',
        id: 'msg_hello_c2',
        ts: Date.now(),
        type: 'connection.hello',
        payload: {
          token,
          client: { name: 'e2e-side-test-c2', version: '1.0.0', platform: 'test' },
          encoding: 'json',
          capabilities: ['replay.v1']
        }
      })
    );
    await waitForClient2((m) => m.kind === 'welcome', 3000, 'client2 welcome frame');

    client2.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'msg_cmd_att_side',
        ts: Date.now(),
        commandId: 'cmd_att_side_1',
        sessionId: streamId,
        type: 'session.attach',
        payload: { lastSeq: null }
      })
    );

    const sideAttResult = await waitForClient2(
      (m) => m.kind === 'result' && m.commandId === 'cmd_att_side_1',
      4000,
      'side session.attach result'
    );
    assert.equal(sideAttResult.payload.state, 'completed');
    assert.equal(sideAttResult.payload.data.attached, true);

    const sideAcks = client2Messages.filter(
      (m) => m.kind === 'ack' && m.sessionId === streamId && m.payload?.state === 'snapshot'
    );
    assert.equal(sideAcks.length, 1, 'Side attach must emit exactly one snapshot ack frame');

    const replayedSideEvents = client2Messages.filter(
      (m) => m.kind === 'event' && m.sessionId === streamId
    );
    assert.ok(replayedSideEvents.length > 0, 'Side attach must replay buffered events');
    const sideSeqs = replayedSideEvents.map((m) => m.seq);
    assert.equal(
      new Set(sideSeqs).size,
      sideSeqs.length,
      `Side attach must yield no duplicate seqs (received: ${JSON.stringify(sideSeqs)})`
    );
    for (let i = 1; i < sideSeqs.length; i++) {
      assert.equal(
        sideSeqs[i],
        sideSeqs[i - 1] + 1,
        `Side attach replayed seqs must be strictly consecutive (${sideSeqs[i]} vs ${sideSeqs[i - 1]})`
      );
    }

    client2.close();
    client2 = null;

    // 11. Close side conversation with Dart helper envelope shape (sessionId = sideId)
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: 'msg_cmd_side_close',
        ts: Date.now(),
        commandId: 'cmd_side_close_1',
        sessionId: sideId,
        type: 'side.close',
        payload: { sideId }
      })
    );

    const closeResult = await waitFor(
      (m) => m.kind === 'result' && m.commandId === 'cmd_side_close_1',
      4000,
      'side.close result'
    );
    assert.equal(closeResult.payload.state, 'completed');
    assert.equal(closeResult.payload.data.closed, true);

    // 12. Verify side.closed event
    const sideClosedEvt = await waitFor(
      (m) => m.kind === 'event' && m.sessionId === streamId && m.type === 'side.closed',
      4000,
      'side.closed event'
    );
    assert.equal(sideClosedEvt.payload.sideId, sideId);
    assert.equal(sideClosedEvt.payload.reason, 'user');
  } finally {
    try {
      client.close();
      if (client2) {
        try { (client2 as any).close(); } catch {}
      }
      manager.closeAll(1000, 'Test finished');
      await registry.closeAll(1000);
      await dispatcher.dispose();
      await new Promise<void>((resolve) => httpServer.close(() => resolve()));
      fs.rmSync(tempDir, { recursive: true, force: true });
    } catch {}
  }
});
