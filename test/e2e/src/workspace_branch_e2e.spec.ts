import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as path from 'node:path';
import * as fs from 'node:fs';
import * as os from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import WebSocket from 'ws';
import { dataOf, listeningPort, parseFrame, type Frame } from './support.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Import agentd components
import { createHttpServer } from '../../../apps/agentd/dist/server/httpServer.js';
import { createWsServer } from '../../../apps/agentd/dist/server/wsServer.js';
import { SessionRegistry } from '../../../apps/agentd/dist/sessions/SessionRegistry.js';
import { Dispatcher } from '../../../apps/agentd/dist/commands/Dispatcher.js';
import { DEFAULT_CONFIG } from '../../../apps/agentd/dist/config/config.js';

function createTempGitRepo(): { root: string; git: (args: string[]) => string; cleanup: () => void } {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-e2e-branch-repo-'));
  const git = (args: string[]) => execFileSync('git', args, { cwd: root, encoding: 'utf8' });
  git(['init', '-q', '-b', 'main']);
  git(['config', 'user.email', 'test@example.com']);
  git(['config', 'user.name', 'PiFrame Test']);
  git(['config', 'core.autocrlf', 'false']);
  fs.writeFileSync(path.join(root, 'readme.md'), '# PiFrame Test\n');
  git(['add', 'readme.md']);
  git(['commit', '-qm', 'initial commit']);
  git(['branch', 'feature/test-e2e']);
  return {
    root,
    git,
    cleanup: () => {
      try {
        fs.rmSync(root, { recursive: true, force: true });
      } catch {}
    }
  };
}

test('E2E: Workspace Branch Operations - listBranches and switchBranch over WebSocket', async () => {
  const fakePiPath = path.resolve(__dirname, '../../../tools/fake-pi/dist/index.js');
  const token = 'test_token_branch_e2e_secret';
  const version = '1.3.0';
  const startedAt = Date.now();
  const repo = createTempGitRepo();

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

  const port = listeningPort(httpServer);

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

  const receivedMessages: Frame[] = [];
  client.on('message', (data) => {
    receivedMessages.push(parseFrame(data));
  });

  // Each step runs real git commands: the stash-and-switch step alone takes
  // about 2.6 s on an idle Windows machine and went past 5 s while other
  // suites ran in parallel (`pnpm -r run test`), so allow 20 s per step.
  const waitForMessage = async (predicate: (msg: Frame) => boolean, timeoutMs = 20000): Promise<Frame> => {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const found = receivedMessages.find(predicate);
      if (found) return found;
      await new Promise((r) => setTimeout(r, 50));
    }
    throw new Error(`Timed out waiting for message matching predicate`);
  };

  try {
    // 1. Send hello handshake
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'hello',
        id: 'msg_hello_01',
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

    const welcome = await waitForMessage((m) => m.kind === 'welcome');
    assert.equal(welcome.kind, 'welcome');

    // 2. Create session in the temp git repo
    const session = await registry.createSession({ cwd: repo.root });
    const sessionId = session.id;

    // 3. listBranches
    const listCmdId = `cmd_list_${Date.now()}`;
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: `msg_${listCmdId}`,
        ts: Date.now(),
        commandId: listCmdId,
        sessionId,
        type: 'workspace.listBranches',
        payload: {}
      })
    );

    const listAck = await waitForMessage((m) => m.kind === 'ack' && m.commandId === listCmdId);
    assert.ok(listAck);

    const listResult = await waitForMessage((m) => m.kind === 'result' && m.commandId === listCmdId);
    assert.equal(listResult.payload.state, 'completed');
    assert.equal(dataOf<{ currentBranch: string }>(listResult).currentBranch, 'main');
    assert.equal(dataOf<{ detached: boolean }>(listResult).detached, false);
    const branchNames = dataOf<{ branches: Array<{ name: string }> }>(listResult).branches.map((b) => b.name);
    assert.ok(branchNames.includes('main'));
    assert.ok(branchNames.includes('feature/test-e2e'));

    // 4. switchBranch clean
    const switchCmdId = `cmd_switch_${Date.now()}`;
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: `msg_${switchCmdId}`,
        ts: Date.now(),
        commandId: switchCmdId,
        sessionId,
        type: 'workspace.switchBranch',
        payload: { branch: 'feature/test-e2e' }
      })
    );

    const switchResult = await waitForMessage((m) => m.kind === 'result' && m.commandId === switchCmdId);
    assert.equal(switchResult.payload.state, 'completed');
    assert.equal(dataOf<{ currentBranch: string }>(switchResult).currentBranch, 'feature/test-e2e');
    assert.equal(dataOf<{ stashed: boolean }>(switchResult).stashed, false);

    // 5. switchBranch with dirty worktree and onDirty 'block'
    fs.writeFileSync(path.join(repo.root, 'dirty.txt'), 'dirty uncommitted\n');
    const dirtyBlockCmdId = `cmd_dirty_blk_${Date.now()}`;
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: `msg_${dirtyBlockCmdId}`,
        ts: Date.now(),
        commandId: dirtyBlockCmdId,
        sessionId,
        type: 'workspace.switchBranch',
        payload: { branch: 'main', onDirty: 'block' }
      })
    );

    const dirtyError = await waitForMessage((m) => m.kind === 'error' && m.commandId === dirtyBlockCmdId);
    assert.equal(dirtyError.payload.code, 'WORKSPACE_DIRTY');
    assert.equal((dirtyError.payload.details as { untrackedFiles?: number } | undefined)?.untrackedFiles, 1);

    const dirtyResult = await waitForMessage((m) => m.kind === 'result' && m.commandId === dirtyBlockCmdId);
    assert.equal(dirtyResult.payload.state, 'rejected');
    const dirtyErrorIdx = receivedMessages.indexOf(dirtyError);
    const dirtyResultIdx = receivedMessages.indexOf(dirtyResult);
    assert.ok(dirtyErrorIdx < dirtyResultIdx, 'Error envelope must precede rejected result envelope');

    // 6. switchBranch with dirty worktree and onDirty 'stash'
    const dirtyStashCmdId = `cmd_dirty_stash_${Date.now()}`;
    client.send(
      JSON.stringify({
        protocol: 1,
        kind: 'command',
        id: `msg_${dirtyStashCmdId}`,
        ts: Date.now(),
        commandId: dirtyStashCmdId,
        sessionId,
        type: 'workspace.switchBranch',
        payload: { branch: 'main', onDirty: 'stash' }
      })
    );

    const stashResult = await waitForMessage((m) => m.kind === 'result' && m.commandId === dirtyStashCmdId);
    assert.equal(stashResult.payload.state, 'completed');
    const stashData = dataOf<{ currentBranch: string; stashed: boolean; stashMessage?: string }>(stashResult);
    assert.equal(stashData.currentBranch, 'main');
    assert.equal(stashData.stashed, true);
    assert.ok(stashData.stashMessage);
  } finally {
    client.close();
    httpServer.close();
    await registry.closeAll();
    repo.cleanup();
  }
});
