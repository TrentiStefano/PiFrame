import test from 'node:test';
import * as assert from 'node:assert/strict';
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
import { AgentsService } from '../../../apps/agentd/dist/pi/agents/AgentsService.js';

function createTempDir(prefix: string): { root: string; cleanup: () => void } {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  return {
    root: dir,
    cleanup: () => {
      try {
        fs.rmSync(dir, { recursive: true, force: true });
      } catch {}
    },
  };
}

test('E2E: Subagent Settings - pi.agents.get and pi.agents.update over WebSocket', async () => {
  const fakePiPath = path.resolve(__dirname, '../../../tools/fake-pi/dist/index.js');
  const token = 'test_token_agents_e2e_secret';
  const version = '1.3.0';
  const startedAt = Date.now();

  const tempAgent = createTempDir('pi-e2e-agent-');
  const tempPiFrame = createTempDir('pi-e2e-piframe-');

  // Setup fake nicobailon package
  const nicoDir = path.join(tempAgent.root, 'npm', 'node_modules', 'pi-subagents');
  const nicoAgentsDir = path.join(nicoDir, 'agents');
  fs.mkdirSync(nicoAgentsDir, { recursive: true });
  fs.writeFileSync(
    path.join(nicoDir, 'package.json'),
    JSON.stringify({ name: 'pi-subagents', version: '0.9.5' })
  );
  fs.writeFileSync(
    path.join(nicoAgentsDir, 'worker.md'),
    `---
name: worker
description: Worker implementation agent
model: fake/fake-model
thinking: high
---
Worker prompt.
`
  );
  fs.writeFileSync(path.join(tempAgent.root, 'settings.json'), '{}');

  const httpServer = createHttpServer({
    config: DEFAULT_CONFIG,
    token,
    version,
    startedAt,
    listener: 'local',
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
    },
  });

  registry = new SessionRegistry({
    piExecutablePath: fakePiPath,
    capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 60000,
    connectionManager: manager,
  });

  const agentsService = new AgentsService({
    agentDir: tempAgent.root,
    piframeDir: tempPiFrame.root,
    getAvailableModels: async () => ({
      models: [
        {
          id: 'fake/fake-model',
          name: 'Fake Pi Model',
          contextWindow: 128000,
          reasoning: true,
          tiers: [64000],
        },
      ],
    }),
  });

  dispatcher = new Dispatcher(
    registry,
    manager,
    undefined,
    undefined,
    undefined,
    agentsService
  );

  const client = new WebSocket(`ws://127.0.0.1:${port}/api/ws`);
  await new Promise<void>((resolve, reject) => {
    client.on('open', resolve);
    client.on('error', reject);
  });

  const receivedMessages: any[] = [];
  client.on('message', (data) => {
    receivedMessages.push(JSON.parse(data.toString()));
  });

  const waitForMessage = async (predicate: (msg: any) => boolean, timeoutMs = 5000): Promise<any> => {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const found = receivedMessages.find(predicate);
      if (found) return found;
      await new Promise((r) => setTimeout(r, 50));
    }
    throw new Error(`Timed out waiting for message matching predicate`);
  };

  try {
    // 1. Hello handshake
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'hello',
        id: 'msg_hello_agents',
        ts: Date.now(),
        type: 'connection.hello',
        payload: {
          token,
          client: { name: 'e2e-test', version: '1.0.0', platform: 'test' },
          encoding: 'json',
          capabilities: ['replay.v1'],
        },
      })
    );

    const welcome = await waitForMessage((m) => m.kind === 'welcome');
    assert.equal(welcome.kind, 'welcome');
    assert.ok(welcome.payload.capabilities.includes('pi.agents.v1'));

    // 2. pi.agents.get
    const getCmdId = `cmd_get_${Date.now()}`;
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: `msg_${getCmdId}`,
        ts: Date.now(),
        commandId: getCmdId,
        sessionId: '@daemon',
        type: 'pi.agents.get',
        payload: {},
      })
    );

    const getAck = await waitForMessage((m) => m.kind === 'ack' && m.commandId === getCmdId);
    assert.ok(getAck);

    const getResult = await waitForMessage((m) => m.kind === 'result' && m.commandId === getCmdId);
    assert.equal(getResult.payload.state, 'completed');
    const getData = getResult.payload.data;
    assert.equal(getData.packages.find((p: any) => p.id === 'pi-subagents')?.installed, true);
    assert.ok(getData.agents.some((a: any) => a.name === 'worker'));

    // 3. pi.agents.update
    const updCmdId = `cmd_upd_${Date.now()}`;
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: `msg_${updCmdId}`,
        ts: Date.now(),
        commandId: updCmdId,
        sessionId: '@daemon',
        type: 'pi.agents.update',
        payload: {
          changes: [
            {
              kind: 'agent',
              name: 'worker',
              model: 'fake/fake-model',
              thinking: 'low',
              contextLimit: 64000,
            },
            {
              kind: 'sessionDefaults',
              model: 'fake/fake-model',
              thinking: 'low',
            },
          ],
        },
      })
    );

    const updAck = await waitForMessage((m) => m.kind === 'ack' && m.commandId === updCmdId);
    assert.ok(updAck);

    const updResult = await waitForMessage((m) => m.kind === 'result' && m.commandId === updCmdId);
    assert.equal(updResult.payload.state, 'completed');
    const updData = updResult.payload.data;
    const updatedWorker = updData.agents.find((a: any) => a.name === 'worker');
    assert.ok(updatedWorker);
    assert.equal(updatedWorker.model.effective, 'fake/fake-model');
    assert.equal(updatedWorker.thinking.effective, 'low');
    assert.equal(updatedWorker.context.limit, 64000);

    // Verify settings on disk
    const settingsOnDisk = JSON.parse(
      fs.readFileSync(path.join(tempAgent.root, 'settings.json'), 'utf8')
    );
    assert.equal(settingsOnDisk.defaultProvider, 'fake');
    assert.equal(settingsOnDisk.defaultModel, 'fake-model');
    assert.equal(settingsOnDisk.defaultThinkingLevel, 'low');
    assert.equal(settingsOnDisk.subagents.agentOverrides.worker.model, 'fake/fake-model');
    assert.equal(settingsOnDisk.subagents.agentOverrides.worker.thinking, 'low');

    // 4. Invalid update: model not available
    const badCmdId = `cmd_bad_${Date.now()}`;
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: `msg_${badCmdId}`,
        ts: Date.now(),
        commandId: badCmdId,
        sessionId: '@daemon',
        type: 'pi.agents.update',
        payload: {
          changes: [
            {
              kind: 'agent',
              name: 'worker',
              model: 'nonexistent/model',
            },
          ],
        },
      })
    );

    const badResult = await waitForMessage((m) => m.kind === 'result' && m.commandId === badCmdId);
    assert.equal(badResult.payload.state, 'failed');
    assert.ok(badResult.payload.error.includes('validation failed'));
  } finally {
    client.close();
    httpServer.close();
    tempAgent.cleanup();
    tempPiFrame.cleanup();
  }
});
