import test from 'node:test';
import * as assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { createHash } from 'node:crypto';
import { ulid } from 'ulid';

import { SideConversationManager } from '../SideConversationManager.js';
import { SideTransport } from '../SideTransport.js';
import {
  renderConversationSnapshot,
  renderMessageBlock,
  SIDE_GUARDRAIL_PREAMBLE
} from '../SideSnapshotRenderer.js';
import { SessionRegistry } from '../../sessions/SessionRegistry.js';
import { Session } from '../../sessions/Session.js';
import { ConnectionManager } from '../../server/wsServer.js';
import { Connection } from '../../server/connection.js';
import { Dispatcher } from '../../commands/Dispatcher.js';
import type { PiTransport } from '../../pi/PiTransport.js';
import type { PiCommand, PiResponse, PiEvent, TransportHealth, PiCapabilities, ExitInfo } from '../../pi/piCommands.js';

class MockWebSocket extends EventEmitter {
  public readyState = 1;
  public sentMessages: string[] = [];
  public closedCode?: number;
  public closedReason?: string;

  public send(data: string | object, cb?: () => void): void {
    const str = typeof data === 'string' ? data : JSON.stringify(data);
    this.sentMessages.push(str);
    if (cb) cb();
  }

  public close(code: number, reason: string): void {
    this.readyState = 3;
    this.closedCode = code;
    this.closedReason = reason;
    this.emit('close');
  }
}

class FakePiTransport implements PiTransport {
  public lastStartOpts?: { cwd: string; args?: string[]; env?: Record<string, string> };
  public sentCommands: PiCommand[] = [];
  public stopCalls: Array<{ graceMs: number }> = [];
  public isAlive = true;
  public mockTools: string[] = ['read', 'grep', 'find', 'ls'];
  public mockModel = { id: 'claude-3-5-sonnet', provider: 'anthropic' };
  public eventQueue: PiEvent[] = [];
  private eventWaiters: Array<(e: PiEvent | null) => void> = [];

  public async start(opts: { cwd: string; args?: string[]; env?: Record<string, string> }): Promise<void> {
    this.lastStartOpts = opts;
    this.isAlive = true;
  }

  public pushEvent(event: PiEvent): void {
    const waiter = this.eventWaiters.shift();
    if (waiter) {
      waiter(event);
    } else {
      this.eventQueue.push(event);
    }
  }

  public async send(cmd: PiCommand): Promise<PiResponse> {
    this.sentCommands.push(cmd);

    if (cmd.command === 'get_state') {
      return {
        id: cmd.id,
        type: 'response',
        command: 'get_state',
        success: true,
        data: {
          model: this.mockModel,
          tools: this.mockTools,
          isStreaming: false,
          isCompacting: false
        }
      };
    }

    if (cmd.command === 'get_messages') {
      return {
        id: cmd.id,
        type: 'response',
        command: 'get_messages',
        success: true,
        data: {
          messages: [
            {
              role: 'user',
              content: [{ type: 'text', text: 'Hello main' }],
              timestamp: Date.now() - 5000
            },
            {
              role: 'assistant',
              content: [
                { type: 'text', text: 'Inspecting files...' },
                {
                  type: 'toolCall',
                  id: 'tc_1',
                  name: 'read',
                  arguments: { path: 'src/app.ts' }
                }
              ],
              timestamp: Date.now() - 3000
            },
            {
              role: 'toolResult',
              toolCallId: 'tc_1',
              toolName: 'read',
              content: [{ type: 'text', text: 'export const x = 1;' }],
              timestamp: Date.now() - 2000
            }
          ]
        }
      };
    }

    if (cmd.command === 'prompt') {
      // Simulate streaming events
      setTimeout(() => {
        this.pushEvent({ type: 'agent_start' });
        this.pushEvent({ type: 'turn_start' });
        this.pushEvent({
          type: 'message_start',
          message: { id: 'msg_side_1', role: 'assistant', timestamp: Date.now() }
        });
        this.pushEvent({
          type: 'message_update',
          assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'Side reply' }
        });
        this.pushEvent({
          type: 'message_end',
          message: { role: 'assistant', content: [{ type: 'text', text: 'Side reply' }] }
        });
        this.pushEvent({ type: 'turn_end' });
        this.pushEvent({ type: 'agent_end', willRetry: false });
        this.pushEvent({ type: 'agent_settled' });
      }, 5);

      return {
        id: cmd.id,
        type: 'response',
        command: 'prompt',
        success: true,
        data: { disposition: 'started' }
      };
    }

    if (cmd.command === 'abort') {
      this.pushEvent({ type: 'agent_end', willRetry: false });
      this.pushEvent({ type: 'agent_settled' });
      return {
        id: cmd.id,
        type: 'response',
        command: 'abort',
        success: true
      };
    }

    return {
      id: cmd.id,
      type: 'response',
      command: cmd.command,
      success: true,
      data: {}
    };
  }

  public async *events(): AsyncIterable<PiEvent> {
    while (this.isAlive) {
      if (this.eventQueue.length > 0) {
        yield this.eventQueue.shift()!;
      } else {
        const ev = await new Promise<PiEvent | null>((resolve) => {
          this.eventWaiters.push(resolve);
        });
        if (ev === null) break;
        yield ev;
      }
    }
  }

  public health(): TransportHealth {
    return {
      alive: this.isAlive,
      pid: 1234,
      lastSeenMs: Date.now()
    };
  }

  public capabilities(): PiCapabilities {
    return {
      version: '0.85.1',
      supported: true,
      modes: ['rpc'],
      features: ['tools']
    };
  }

  public async stop(opts: { graceMs: number }): Promise<ExitInfo> {
    this.stopCalls.push(opts);
    this.isAlive = false;
    for (const waiter of this.eventWaiters) {
      waiter(null);
    }
    this.eventWaiters = [];
    return { exitCode: 0, signal: null, lastStderr: [] };
  }
}

function createSideTestContext() {
  const tmpBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-side-test-'));
  const connManager = new ConnectionManager();
  const sessionRegistry = new SessionRegistry({
    piExecutablePath: 'node',
    capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 60000,
    connectionManager: connManager
  });

  const fakeTransports: FakePiTransport[] = [];
  const transportFactory = () => {
    const t = new FakePiTransport();
    fakeTransports.push(t);
    return t;
  };

  const sideManager = new SideConversationManager({
    piExecutablePath: 'node',
    connectionManager: connManager,
    sessionRegistry,
    baseDir: tmpBaseDir,
    defaultIdleTimeoutMs: 10 * 60 * 1000,
    transportFactory
  });

  const dispatcher = new Dispatcher(
    sessionRegistry,
    connManager,
    undefined,
    undefined,
    undefined,
    undefined,
    sideManager
  );

  const ws = new MockWebSocket();
  const conn = new Connection({
    ws: ws as any,
    expectedToken: 'test-token',
    daemonVersion: '0.1.0',
    startedAt: Date.now(),
    piInfo: { path: 'node', version: '0.85.1', supported: true },
    onCommand: async () => {},
    onClose: () => {}
  });
  conn.state = 'ready';
  connManager.add(conn);

  const cleanup = () => {
    try {
      fs.rmSync(tmpBaseDir, { recursive: true, force: true });
    } catch {}
  };

  return {
    tmpBaseDir,
    connManager,
    sessionRegistry,
    sideManager,
    dispatcher,
    ws,
    conn,
    fakeTransports,
    cleanup
  };
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test('SideTransport RPC allowlist: allows prompt, abort, get_state; blocks everything else', async () => {
  const inner = new FakePiTransport();
  const side = new SideTransport(inner);

  // Allowed
  const sRes = await side.send({ command: 'get_state' });
  assert.equal(sRes.success, true);

  const pRes = await side.send({ command: 'prompt', message: 'test' });
  assert.equal(pRes.success, true);

  const aRes = await side.send({ command: 'abort' });
  assert.equal(aRes.success, true);

  // Blocked commands
  const blockedCommands = ['switch_session', 'fork', 'bash', 'set_model', 'compact', 'steer'];
  for (const cmd of blockedCommands) {
    await assert.rejects(
      async () => {
        await side.send({ command: cmd });
      },
      (err: any) => {
        assert.equal(err.code, 'SIDE_RPC_BLOCKED');
        assert.ok(err.message.includes('blocked for side conversation worker'));
        return true;
      }
    );
  }
});

test('SideSnapshotRenderer: formats user, assistant, tool summaries, truncates tool output', () => {
  const messages = [
    {
      role: 'user',
      content: [{ type: 'text', text: 'Where is main defined?' }]
    },
    {
      role: 'assistant',
      content: [
        { type: 'text', text: 'Let me search the files.' },
        {
          type: 'toolCall',
          id: 'tc_1',
          name: 'grep',
          arguments: { pattern: 'function main', path: 'src/' }
        }
      ]
    },
    {
      role: 'toolResult',
      toolName: 'grep',
      content: [{ type: 'text', text: 'A'.repeat(800) }]
    }
  ];

  const rendered = renderConversationSnapshot({ messages });

  // Preamble present
  assert.ok(rendered.includes(SIDE_GUARDRAIL_PREAMBLE));

  // User formatted
  assert.ok(rendered.includes('### User\nWhere is main defined?'));

  // Assistant & Tool summary formatted
  assert.ok(rendered.includes('### Assistant\nLet me search the files.\ntool(grep): function main'));

  // Tool result truncated to 500 chars with note
  assert.ok(rendered.includes('tool_result(grep): '));
  assert.ok(rendered.includes('... [output truncated]'));
});

test('SideSnapshotRenderer: caps snapshot to maxChars, keeps most recent, notes truncation', () => {
  const messages: any[] = [];
  for (let i = 1; i <= 20; i++) {
    messages.push({
      role: 'user',
      content: [{ type: 'text', text: `Question number ${i} with extra padding words` }]
    });
    messages.push({
      role: 'assistant',
      content: [{ type: 'text', text: `Answer number ${i} with extra padding words` }]
    });
  }

  // Set a small limit of 400 chars
  const rendered = renderConversationSnapshot({ messages, maxChars: 400 });

  assert.ok(rendered.includes('[Snapshot truncated: displaying the most recent conversation entries'));
  // Most recent entries must be present
  assert.ok(rendered.includes('Question number 20'));
  assert.ok(rendered.includes('Answer number 20'));
  // Oldest entries must have been dropped
  assert.ok(!rendered.includes('Question number 1 with'));
});

test('spawn args include exact read-only flags and exclude bash/edit/write', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Main Session'
    });
    parentSession.model = { id: 'claude-3-5-sonnet', provider: 'anthropic' };
    parentSession.thinkingLevel = 'high';

    const { sideId, streamId } = await ctx.sideManager.open({
      parentSessionId: parentSession.id,
      conn: ctx.conn
    });

    assert.ok(sideId.startsWith('side_'));
    assert.equal(streamId, sideId);

    const transport = ctx.fakeTransports[0];
    assert.ok(transport);
    const args = transport.lastStartOpts?.args || [];

    // Verify required flags
    assert.deepEqual(args.slice(0, 8), [
      '--mode', 'rpc',
      '--no-session',
      '--tools', 'read,grep,find,ls',
      '--no-mcp',
      '--no-extensions',
      '--no-skills'
    ]);
    assert.ok(args.includes('--no-skills'));
    assert.ok(args.includes('--append-system-prompt'));
    assert.ok(args.includes('--model'));
    assert.ok(args.includes('anthropic/claude-3-5-sonnet'));
    assert.ok(args.includes('--thinking'));
    assert.ok(args.includes('high'));

    // Verify dangerous tools and context limit extension are NOT in args
    assert.ok(!args.includes('bash'));
    assert.ok(!args.includes('edit'));
    assert.ok(!args.includes('write'));
    assert.ok(!args.join(' ').includes('contextLimitExtension'));

    // Context file permissions
    const promptPathIdx = args.indexOf('--append-system-prompt');
    const contextFilePath = args[promptPathIdx + 1];
    assert.ok(fs.existsSync(contextFilePath));
    const stat = fs.statSync(contextFilePath);
    // On POSIX mode & 0o777 is 0o600; on Windows stat.mode contains file type bits
    assert.ok(stat.isFile());

    await ctx.sideManager.close(sideId, 'user');
  } finally {
    ctx.cleanup();
  }
});

test('Unsafe tools exposed via get_state triggers SIDE_UNSAFE_TOOLS and aborts', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Main Session'
    });

    // Make transport expose bash
    const unsafeTransportFactory = () => {
      const t = new FakePiTransport();
      t.mockTools = ['read', 'bash']; // UNSAFE!
      return t;
    };

    const sideMgr = new SideConversationManager({
      piExecutablePath: 'node',
      connectionManager: ctx.connManager,
      sessionRegistry: ctx.sessionRegistry,
      baseDir: ctx.tmpBaseDir,
      transportFactory: unsafeTransportFactory
    });

    await assert.rejects(
      async () => {
        await sideMgr.open({ parentSessionId: parentSession.id });
      },
      (err: any) => {
        assert.equal(err.code, 'SIDE_UNSAFE_TOOLS');
        assert.ok(err.message.includes('Unsafe tool "bash"'));
        return true;
      }
    );

    // Verify temp directory was cleaned up
    const sideRuntimeDir = path.join(ctx.tmpBaseDir, 'runtime', 'side');
    if (fs.existsSync(sideRuntimeDir)) {
      const remaining = fs.readdirSync(sideRuntimeDir);
      assert.equal(remaining.length, 0);
    }
  } finally {
    ctx.cleanup();
  }
});

test('Isolation: main session file is byte-identical before and after open+prompt+close', async () => {
  const ctx = createSideTestContext();
  try {
    const sessionFileDir = path.join(ctx.tmpBaseDir, 'sessions');
    fs.mkdirSync(sessionFileDir, { recursive: true });
    const sessionFile = path.join(sessionFileDir, 'test-session.jsonl');
    const initialContent = JSON.stringify({ id: 'msg-01', role: 'user', content: 'Original message' }) + '\n';
    fs.writeFileSync(sessionFile, initialContent, 'utf8');

    const beforeHash = createHash('sha256').update(fs.readFileSync(sessionFile)).digest('hex');

    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Isolation Test'
    });
    parentSession.sessionFile = sessionFile;

    const { sideId } = await ctx.sideManager.open({
      parentSessionId: parentSession.id,
      question: 'Can you read my session?'
    });

    await ctx.sideManager.prompt(sideId, 'Second question');
    await ctx.sideManager.close(sideId, 'user');

    const afterContent = fs.readFileSync(sessionFile);
    const afterHash = createHash('sha256').update(afterContent).digest('hex');

    assert.equal(beforeHash, afterHash, 'Main session file must be byte-for-byte identical');
  } finally {
    ctx.cleanup();
  }
});

test('Isolation: main session journal receives NO side events', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Journal Isolation Test'
    });

    const initialSeq = parentSession.journal.currentSeq;

    const { sideId, streamId } = await ctx.sideManager.open({
      parentSessionId: parentSession.id,
      conn: ctx.conn
    });

    await ctx.sideManager.prompt(sideId, 'Question for side');
    // Allow streamed events to process
    await new Promise((r) => setTimeout(r, 20));
    await ctx.sideManager.close(sideId, 'user');

    assert.equal(
      parentSession.journal.currentSeq,
      initialSeq,
      'Main session journal sequence must not change from side operations'
    );

    // Verify side events were delivered to connection on streamId, not main session
    const sideEvents = ctx.ws.sentMessages
      .map((m) => JSON.parse(m))
      .filter((m) => m.sessionId === streamId);

    assert.ok(sideEvents.length > 0);
    assert.ok(sideEvents.some((e) => e.type === 'side.opened'));
    assert.ok(sideEvents.some((e) => e.type === 'side.closed'));
  } finally {
    ctx.cleanup();
  }
});

test('Lifecycle: close deletes temp dir and kills worker', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Temp Dir Test'
    });

    const { sideId } = await ctx.sideManager.open({
      parentSessionId: parentSession.id
    });

    const contextDir = path.join(ctx.tmpBaseDir, 'runtime', 'side', sideId);
    assert.ok(fs.existsSync(contextDir), 'Temp runtime context dir must exist while open');

    await ctx.sideManager.close(sideId, 'user');

    assert.ok(!fs.existsSync(contextDir), 'Temp runtime context dir must be deleted on close');
    assert.equal(ctx.fakeTransports[0].stopCalls.length, 1, 'Worker stop must be called');
  } finally {
    ctx.cleanup();
  }
});

test('Lifecycle: idle timeout closes side thread with reason idle', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Idle Test'
    });

    // Create manager with 50ms idle timeout
    const sideMgr = new SideConversationManager({
      piExecutablePath: 'node',
      connectionManager: ctx.connManager,
      sessionRegistry: ctx.sessionRegistry,
      baseDir: ctx.tmpBaseDir,
      defaultIdleTimeoutMs: 50,
      transportFactory: () => new FakePiTransport()
    });

    const { sideId } = await sideMgr.open({
      parentSessionId: parentSession.id,
      conn: ctx.conn
    });

    assert.ok(sideMgr.getSide(sideId));

    // Wait 100ms for idle timeout to fire
    await new Promise((r) => setTimeout(r, 120));

    assert.equal(sideMgr.getSide(sideId), undefined, 'Thread should be closed after idle timeout');

    const closedEvent = ctx.ws.sentMessages
      .map((m) => JSON.parse(m))
      .find((m) => m.type === 'side.closed');

    assert.ok(closedEvent);
    assert.equal(closedEvent.payload.reason, 'idle');
  } finally {
    ctx.cleanup();
  }
});

test('Lifecycle: parent close triggers side close with reason parentClosed', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Parent Close Test'
    });

    const { sideId } = await ctx.sideManager.open({
      parentSessionId: parentSession.id,
      conn: ctx.conn
    });

    assert.ok(ctx.sideManager.getSide(sideId));

    // Close parent session
    await ctx.sessionRegistry.closeWorker(parentSession.id);

    assert.equal(ctx.sideManager.getSide(sideId), undefined);

    const closedEvent = ctx.ws.sentMessages
      .map((m) => JSON.parse(m))
      .find((m) => m.type === 'side.closed');

    assert.ok(closedEvent);
    assert.equal(closedEvent.payload.reason, 'parentClosed');
  } finally {
    ctx.cleanup();
  }
});

test('One-per-parent: opening again returns existing sideId and streamId', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'One Per Parent Test'
    });

    const res1 = await ctx.sideManager.open({ parentSessionId: parentSession.id });
    const res2 = await ctx.sideManager.open({ parentSessionId: parentSession.id });

    assert.equal(res1.sideId, res2.sideId);
    assert.equal(res1.streamId, res2.streamId);
    assert.equal(ctx.fakeTransports.length, 1, 'Only one worker spawned for parent');

    await ctx.sideManager.close(res1.sideId, 'user');
  } finally {
    ctx.cleanup();
  }
});

test('Limits: max 4 total concurrent side threads', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSessions: Session[] = [];
    for (let i = 1; i <= 5; i++) {
      parentSessions.push(
        await ctx.sessionRegistry.createSession({
          cwd: ctx.tmpBaseDir,
          name: `Parent ${i}`
        })
      );
    }

    // Open 4
    for (let i = 0; i < 4; i++) {
      await ctx.sideManager.open({ parentSessionId: parentSessions[i].id });
    }

    assert.equal(ctx.sideManager.getActiveCount(), 4);

    // 5th must fail
    await assert.rejects(
      async () => {
        await ctx.sideManager.open({ parentSessionId: parentSessions[4].id });
      },
      (err: any) => {
        assert.equal(err.code, 'SIDE_LIMIT_REACHED');
        return true;
      }
    );

    await ctx.sideManager.dispose();
    assert.equal(ctx.sideManager.getActiveCount(), 0);
  } finally {
    ctx.cleanup();
  }
});

test('Dispatcher: remote view mode forbidden for open/prompt, allowed for abort/close', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Remote Auth Test'
    });

    // Mock remote manager returning view mode device
    const mockAuthManager = {
      getDevice: (id: string) => ({ id, mode: 'view' })
    };
    (ctx.dispatcher as any).remoteManager = {
      getAuthManager: () => mockAuthManager
    };

    const remoteWs = new MockWebSocket();
    const remoteViewConn = new Connection({
      ws: remoteWs as any,
      expectedToken: 'remote-tok',
      daemonVersion: '0.1.0',
      startedAt: Date.now(),
      piInfo: { path: 'node', version: '0.85.1', supported: true },
      onCommand: async () => {},
      onClose: () => {}
    });
    remoteViewConn.isRemote = true;
    remoteViewConn.deviceId = 'dev_view_01';
    remoteViewConn.state = 'ready';
    ctx.connManager.add(remoteViewConn);

    // Helper to send command via dispatcher and return parsed result
    const send = async (c: Connection, mockWs: MockWebSocket, type: string, payload: any, sId?: string) => {
      const start = mockWs.sentMessages.length;
      await ctx.dispatcher.handle(c, {
        protocol: 1,
        kind: 'command',
        id: `cmd_${ulid()}`,
        ts: Date.now(),
        commandId: `cid_${ulid()}`,
        sessionId: sId,
        type,
        payload
      } as any);
      const msgs = mockWs.sentMessages.slice(start).map((m: string) => JSON.parse(m));
      const errorMsg = msgs.find((m: any) => m.kind === 'error');
      const resultMsg = msgs.find((m: any) => m.kind === 'result');
      return {
        error: errorMsg?.payload,
        result: resultMsg?.payload,
        data: resultMsg?.payload?.data
      };
    };

    // 1. side.open in view mode -> REMOTE_FORBIDDEN
    const openRes = await send(remoteViewConn, remoteWs, 'side.open', { sessionId: parentSession.id });
    assert.equal(openRes.result?.state, 'rejected');
    assert.equal(openRes.error?.code, 'REMOTE_FORBIDDEN');

    // Open from local connection
    const localOpenRes = await send(ctx.conn, ctx.ws, 'side.open', { sessionId: parentSession.id });
    assert.equal(localOpenRes.result?.state, 'completed');
    const sideId = localOpenRes.data?.sideId;

    // 2. side.prompt in view mode -> REMOTE_FORBIDDEN
    const promptRes = await send(remoteViewConn, remoteWs, 'side.prompt', { sideId, text: 'Hello' });
    assert.equal(promptRes.result?.state, 'rejected');
    assert.equal(promptRes.error?.code, 'REMOTE_FORBIDDEN');

    // 3. side.abort in view mode -> ALLOWED
    const abortRes = await send(remoteViewConn, remoteWs, 'side.abort', { sideId });
    assert.equal(abortRes.result?.state, 'completed');
    assert.equal(abortRes.data?.aborted, true);

    // 4. side.close in view mode -> ALLOWED
    const closeRes = await send(remoteViewConn, remoteWs, 'side.close', { sideId });
    assert.equal(closeRes.result?.state, 'completed');
    assert.equal(closeRes.data?.closed, true);

    // 5. Remote in control mode -> open and prompt ALLOWED
    const remoteCtrlWs = new MockWebSocket();
    const remoteControlConn = new Connection({
      ws: remoteCtrlWs as any,
      expectedToken: 'remote-tok-2',
      daemonVersion: '0.1.0',
      startedAt: Date.now(),
      piInfo: { path: 'node', version: '0.85.1', supported: true },
      onCommand: async () => {},
      onClose: () => {}
    });
    remoteControlConn.isRemote = true;
    remoteControlConn.deviceId = 'dev_ctrl_01';
    remoteControlConn.state = 'ready';
    ctx.connManager.add(remoteControlConn);
    mockAuthManager.getDevice = (id: string) => ({ id, mode: 'control' } as any);

    const ctrlOpenRes = await send(remoteControlConn, remoteCtrlWs, 'side.open', { sessionId: parentSession.id });
    assert.equal(ctrlOpenRes.result?.state, 'completed');
    assert.ok(ctrlOpenRes.data?.sideId);

    const ctrlPromptRes = await send(remoteControlConn, remoteCtrlWs, 'side.prompt', {
      sideId: ctrlOpenRes.data?.sideId,
      text: 'Question from control remote'
    });
    assert.equal(ctrlPromptRes.result?.state, 'completed');
    assert.equal(ctrlPromptRes.data?.prompted, true);

    await ctx.sideManager.close(ctrlOpenRes.data?.sideId, 'user');
  } finally {
    ctx.cleanup();
  }
});

test('Dispatcher: commands targeting side stream rejected with SIDE_STREAM_READ_ONLY', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Stream Protection Test'
    });

    const { sideId, streamId } = await ctx.sideManager.open({
      parentSessionId: parentSession.id,
      conn: ctx.conn
    });

    // Helper to send command via dispatcher and return parsed result
    const send = async (c: Connection, mockWs: MockWebSocket, type: string, payload: any, sId?: string) => {
      const start = mockWs.sentMessages.length;
      await ctx.dispatcher.handle(c, {
        protocol: 1,
        kind: 'command',
        id: `cmd_${ulid()}`,
        ts: Date.now(),
        commandId: `cid_${ulid()}`,
        sessionId: sId,
        type,
        payload
      } as any);
      const msgs = mockWs.sentMessages.slice(start).map((m: string) => JSON.parse(m));
      const errorMsg = msgs.find((m: any) => m.kind === 'error');
      const resultMsg = msgs.find((m: any) => m.kind === 'result');
      return {
        error: errorMsg?.payload,
        result: resultMsg?.payload,
        data: resultMsg?.payload?.data
      };
    };

    // 1. Mutating command targeting streamId rejected
    const promptRes = await send(ctx.conn, ctx.ws, 'agent.prompt', { text: 'Direct prompt to stream' }, streamId);
    assert.equal(promptRes.result?.state, 'rejected');
    assert.equal(promptRes.error?.code, 'SIDE_STREAM_READ_ONLY');

    // 2. Workspace command targeting streamId rejected
    const wsRes = await send(ctx.conn, ctx.ws, 'workspace.listFiles', {}, streamId);
    assert.equal(wsRes.result?.state, 'rejected');
    assert.equal(wsRes.error?.code, 'SIDE_STREAM_READ_ONLY');

    // 3. side.* for unknown sideId rejected with SIDE_NOT_FOUND
    const unknownRes = await send(ctx.conn, ctx.ws, 'side.prompt', { sideId: 'side_UNKNOWN_999', text: 'Where am I?' });
    assert.equal(unknownRes.result?.state, 'rejected');
    assert.equal(unknownRes.error?.code, 'SIDE_NOT_FOUND');

    // 4. session.attach to streamId is permitted and replays events
    const attachRes = await send(ctx.conn, ctx.ws, 'session.attach', { lastSeq: null }, streamId);
    assert.equal(attachRes.result?.state, 'completed');
    assert.equal(attachRes.data?.attached, true);

    await ctx.sideManager.close(sideId, 'user');
  } finally {
    ctx.cleanup();
  }
});

test('Dispatcher: side.prompt, side.abort, side.close allowed when sessionId = sideId', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Side Command Envelope Test'
    });

    const { sideId, streamId } = await ctx.sideManager.open({
      parentSessionId: parentSession.id,
      conn: ctx.conn
    });

    const send = async (type: string, payload: any, sId?: string) => {
      const start = ctx.ws.sentMessages.length;
      await ctx.dispatcher.handle(ctx.conn, {
        protocol: 1,
        kind: 'command',
        id: `cmd_${ulid()}`,
        ts: Date.now(),
        commandId: `cid_${ulid()}`,
        sessionId: sId,
        type,
        payload
      } as any);
      const msgs = ctx.ws.sentMessages.slice(start).map((m: string) => JSON.parse(m));
      return {
        error: msgs.find((m: any) => m.kind === 'error')?.payload,
        result: msgs.find((m: any) => m.kind === 'result')?.payload,
        data: msgs.find((m: any) => m.kind === 'result')?.payload?.data
      };
    };

    // 1. side.prompt with sessionId = sideId
    const promptRes = await send('side.prompt', { sideId, text: 'Hello side conversation' }, sideId);
    assert.equal(promptRes.result?.state, 'completed');
    assert.equal(promptRes.data?.prompted, true);

    // 2. side.abort with sessionId = sideId
    const abortRes = await send('side.abort', { sideId }, sideId);
    assert.equal(abortRes.result?.state, 'completed');
    assert.equal(abortRes.data?.aborted, true);

    // 3. side.close with sessionId = sideId
    const closeRes = await send('side.close', { sideId }, sideId);
    assert.equal(closeRes.result?.state, 'completed');
    assert.equal(closeRes.data?.closed, true);

    // Verify side thread is indeed closed
    assert.equal(ctx.sideManager.hasStream(streamId), false);
  } finally {
    ctx.cleanup();
  }
});

test('Dispatcher: side commands on side stream reject mismatched payload.sideId', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Side Mismatch Test'
    });

    const { sideId } = await ctx.sideManager.open({
      parentSessionId: parentSession.id,
      conn: ctx.conn
    });

    const send = async (type: string, payload: any, sId?: string) => {
      const start = ctx.ws.sentMessages.length;
      await ctx.dispatcher.handle(ctx.conn, {
        protocol: 1,
        kind: 'command',
        id: `cmd_${ulid()}`,
        ts: Date.now(),
        commandId: `cid_${ulid()}`,
        sessionId: sId,
        type,
        payload
      } as any);
      const msgs = ctx.ws.sentMessages.slice(start).map((m: string) => JSON.parse(m));
      return {
        error: msgs.find((m: any) => m.kind === 'error')?.payload,
        result: msgs.find((m: any) => m.kind === 'result')?.payload
      };
    };

    // side.prompt with mismatched sideId
    const promptMismatch = await send('side.prompt', { sideId: 'side_OTHER', text: 'hi' }, sideId);
    assert.equal(promptMismatch.result?.state, 'rejected');
    assert.equal(promptMismatch.error?.code, 'COMMAND_REJECTED');

    // side.abort with mismatched sideId
    const abortMismatch = await send('side.abort', { sideId: 'side_OTHER' }, sideId);
    assert.equal(abortMismatch.result?.state, 'rejected');
    assert.equal(abortMismatch.error?.code, 'COMMAND_REJECTED');

    // side.close with mismatched sideId
    const closeMismatch = await send('side.close', { sideId: 'side_OTHER' }, sideId);
    assert.equal(closeMismatch.result?.state, 'rejected');
    assert.equal(closeMismatch.error?.code, 'COMMAND_REJECTED');

    await ctx.sideManager.close(sideId, 'user');
  } finally {
    ctx.cleanup();
  }
});

test('Dispatcher: agent.prompt and workspace.saveFile on side stream are rejected', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Side Stream Read Only Test'
    });

    const { sideId } = await ctx.sideManager.open({
      parentSessionId: parentSession.id,
      conn: ctx.conn
    });

    const send = async (type: string, payload: any, sId?: string) => {
      const start = ctx.ws.sentMessages.length;
      await ctx.dispatcher.handle(ctx.conn, {
        protocol: 1,
        kind: 'command',
        id: `cmd_${ulid()}`,
        ts: Date.now(),
        commandId: `cid_${ulid()}`,
        sessionId: sId,
        type,
        payload
      } as any);
      const msgs = ctx.ws.sentMessages.slice(start).map((m: string) => JSON.parse(m));
      return {
        error: msgs.find((m: any) => m.kind === 'error')?.payload,
        result: msgs.find((m: any) => m.kind === 'result')?.payload
      };
    };

    const promptRes = await send('agent.prompt', { text: 'try prompt' }, sideId);
    assert.equal(promptRes.result?.state, 'rejected');
    assert.equal(promptRes.error?.code, 'SIDE_STREAM_READ_ONLY');

    const saveRes = await send(
      'workspace.saveFile',
      { path: 'test.txt', content: 'test', revision: '0'.repeat(64) },
      sideId
    );
    assert.equal(saveRes.result?.state, 'rejected');
    assert.equal(saveRes.error?.code, 'SIDE_STREAM_READ_ONLY');

    await ctx.sideManager.close(sideId, 'user');
  } finally {
    ctx.cleanup();
  }
});

test('SideConversationManager: cleans stale runtime side directories on construction', async () => {
  const tmpBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-stale-test-'));
  try {
    const sideRuntimeDir = path.join(tmpBaseDir, 'runtime', 'side');
    const stale1 = path.join(sideRuntimeDir, 'stale_thread_1');
    const stale2 = path.join(sideRuntimeDir, 'stale_thread_2');
    const otherDir = path.join(tmpBaseDir, 'runtime', 'other');

    fs.mkdirSync(stale1, { recursive: true });
    fs.writeFileSync(path.join(stale1, 'context.md'), 'stale 1');
    fs.mkdirSync(stale2, { recursive: true });
    fs.writeFileSync(path.join(stale2, 'context.md'), 'stale 2');
    fs.mkdirSync(otherDir, { recursive: true });
    fs.writeFileSync(path.join(otherDir, 'keep.txt'), 'keep me');

    assert.ok(fs.existsSync(stale1));
    assert.ok(fs.existsSync(stale2));
    assert.ok(fs.existsSync(otherDir));

    const connManager = new ConnectionManager();
    const sessionRegistry = new SessionRegistry({
      piExecutablePath: 'node',
      capabilities: { version: '0.85.1', supported: true, modes: ['rpc'], features: [] },
      workerIdleTimeoutMs: 60000,
      connectionManager: connManager
    });

    const manager = new SideConversationManager({
      piExecutablePath: 'node',
      connectionManager: connManager,
      sessionRegistry,
      baseDir: tmpBaseDir
    });

    assert.equal(fs.existsSync(stale1), false, 'stale_thread_1 should be removed');
    assert.equal(fs.existsSync(stale2), false, 'stale_thread_2 should be removed');
    assert.equal(fs.existsSync(otherDir), true, 'other runtime dirs should be preserved');
    await manager.dispose();
  } finally {
    fs.rmSync(tmpBaseDir, { recursive: true, force: true });
  }
});

test('SideConversationManager: auto-prompt rejection in open() emits error and closes gracefully', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Auto-prompt error test'
    });

    // Configure fake transport to reject prompts
    const originalSend = FakePiTransport.prototype.send;
    FakePiTransport.prototype.send = async function (cmd: PiCommand): Promise<PiResponse> {
      if (cmd.command === 'prompt') {
        throw new Error('Simulated prompt failure in worker');
      }
      return originalSend.call(this, cmd);
    };

    try {
      const { streamId } = await ctx.sideManager.open({
        parentSessionId: parentSession.id,
        question: 'Trigger failure',
        conn: ctx.conn
      });

      // Wait a tick for prompt floating promise rejection to be handled
      await new Promise((r) => setTimeout(r, 100));

      const messages = ctx.ws.sentMessages.map((m) => JSON.parse(m));
      const diagMsg = messages.find(
        (m: any) => m.type === 'worker.diagnostic' && m.sessionId === streamId && m.payload?.level === 'error'
      );
      assert.ok(diagMsg, 'Must emit worker.diagnostic error on side stream');
      assert.ok(diagMsg.payload.message.includes('Simulated prompt failure'));

      const closeMsg = messages.find(
        (m: any) => m.type === 'side.closed' && m.sessionId === streamId && m.payload?.reason === 'error'
      );
      assert.ok(closeMsg, 'Must emit side.closed with reason: error');
      assert.equal(ctx.sideManager.hasStream(streamId), false);
    } finally {
      FakePiTransport.prototype.send = originalSend;
    }
  } finally {
    ctx.cleanup();
  }
});

test('Dispatcher.dispose(): terminates side workers and cleans up temp dirs', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Dispose Test'
    });

    const { sideId } = await ctx.sideManager.open({
      parentSessionId: parentSession.id,
      conn: ctx.conn
    });

    const contextDir = path.join(ctx.tmpBaseDir, 'runtime', 'side', sideId);
    assert.ok(fs.existsSync(contextDir), 'Context dir should exist while side thread is active');

    // Await async dispose
    await ctx.dispatcher.dispose();

    assert.equal(fs.existsSync(contextDir), false, 'Context dir should be deleted on dispose');
    assert.equal(ctx.sideManager.getActiveCount(), 0, 'Side conversations should be empty after dispose');
  } finally {
    ctx.cleanup();
  }
});

test('SideConversationManager: session.attach yields exactly one replay of buffered events (no duplicate seq)', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({
      cwd: ctx.tmpBaseDir,
      name: 'Side Attach Replay Test'
    });

    const { sideId, streamId } = await ctx.sideManager.open({
      parentSessionId: parentSession.id,
      conn: ctx.conn
    });

    // Send a prompt to populate thread.eventsBuffer with streaming events
    await ctx.sideManager.prompt(sideId, 'Hello side agent');
    // Wait for streaming events to settle into buffer
    await new Promise((r) => setTimeout(r, 60));

    const thread = ctx.sideManager.getSide(sideId)!;
    assert.ok(thread.eventsBuffer.length > 0, 'Thread must have buffered events');

    // Create a new connection wired as in main.ts
    const ws2 = new MockWebSocket();
    const conn2 = new Connection({
      ws: ws2 as any,
      expectedToken: 'test-token',
      daemonVersion: '0.1.0',
      startedAt: Date.now(),
      piInfo: { path: 'node', version: '0.85.1', supported: true },
      onCommand: async (c, cmd) => {
        await ctx.dispatcher.handle(c, cmd);
      },
      onAttach: async (c, sid, lastSeq, commandId) => {
        if (sid.startsWith('side_') || ctx.dispatcher.getSideManager().hasStream(sid)) {
          await ctx.dispatcher.getSideManager().handleAttach(sid, c, lastSeq, commandId);
        } else {
          await ctx.sessionRegistry.attachClient(sid, c, lastSeq, commandId);
        }
      },
      onDetach: async (c, sid) => {
        if (sid.startsWith('side_') || ctx.dispatcher.getSideManager().hasStream(sid)) {
          ctx.dispatcher.getSideManager().handleDetach(sid, c);
        } else {
          await ctx.sessionRegistry.detachClient(sid, c);
        }
      },
      onClose: () => {}
    });
    conn2.state = 'ready';

    // 1. Simulate session.attach command with lastSeq = null (snapshot replay)
    const attachCommandId = `att_${ulid()}`;
    await (conn2 as any).executeCommand({
      protocol: 1,
      kind: 'command',
      id: `msg_${ulid()}`,
      ts: Date.now(),
      commandId: attachCommandId,
      sessionId: streamId,
      type: 'session.attach',
      payload: { lastSeq: null }
    });

    const messages = ws2.sentMessages.map((m: string) => JSON.parse(m));

    // Verify exactly one snapshot ack message from handleAttach (no duplicate acks)
    const snapshotAcks = messages.filter(
      (m: any) => m.kind === 'ack' && m.commandId === attachCommandId && m.payload?.state === 'snapshot'
    );
    assert.equal(snapshotAcks.length, 1, 'Must receive exactly one snapshot ack for attach command');

    // Verify replayed events: exactly one replay, count matches thread.eventsBuffer, no duplicate seq
    const replayedEvents = messages.filter((m: any) => m.kind === 'event' && m.sessionId === streamId);
    assert.equal(
      replayedEvents.length,
      thread.eventsBuffer.length,
      'Replayed event count must match thread eventsBuffer length exactly once'
    );

    const seqs = replayedEvents.map((m: any) => m.seq);
    assert.equal(new Set(seqs).size, seqs.length, 'Replayed event seqs must have NO duplicates');
    for (let i = 1; i < seqs.length; i++) {
      assert.equal(seqs[i], seqs[i - 1] + 1, 'Replayed seq numbers must be strictly consecutive');
    }

    // Verify command result completed
    const resultMsg = messages.find((m: any) => m.kind === 'result' && m.commandId === attachCommandId);
    assert.ok(resultMsg, 'Must receive command result for attach');
    assert.equal(resultMsg.payload?.state, 'completed');
    assert.equal(resultMsg.payload?.data?.attached, true);

    // Verify subsequent handleAttach with same commandId is deduped (no extra messages)
    const msgCountBefore = ws2.sentMessages.length;
    await ctx.dispatcher.getSideManager().handleAttach(streamId, conn2, null, attachCommandId);
    assert.equal(ws2.sentMessages.length, msgCountBefore, 'Subsequent handleAttach with same commandId must be deduped');

    // 2. Also verify resume attach with lastSeq
    const ws3 = new MockWebSocket();
    const conn3 = new Connection({
      ws: ws3 as any,
      expectedToken: 'test-token',
      daemonVersion: '0.1.0',
      startedAt: Date.now(),
      piInfo: { path: 'node', version: '0.85.1', supported: true },
      onCommand: async (c, cmd) => {
        await ctx.dispatcher.handle(c, cmd);
      },
      onAttach: async (c, sid, lastSeq, commandId) => {
        if (sid.startsWith('side_') || ctx.dispatcher.getSideManager().hasStream(sid)) {
          await ctx.dispatcher.getSideManager().handleAttach(sid, c, lastSeq, commandId);
        } else {
          await ctx.sessionRegistry.attachClient(sid, c, lastSeq, commandId);
        }
      },
      onDetach: async (c, sid) => {
        if (sid.startsWith('side_') || ctx.dispatcher.getSideManager().hasStream(sid)) {
          ctx.dispatcher.getSideManager().handleDetach(sid, c);
        } else {
          await ctx.sessionRegistry.detachClient(sid, c);
        }
      },
      onClose: () => {}
    });
    conn3.state = 'ready';

    const resumeSeq = seqs[Math.floor(seqs.length / 2)];
    const resumeCommandId = `att_resume_${ulid()}`;
    await (conn3 as any).executeCommand({
      protocol: 1,
      kind: 'command',
      id: `msg_${ulid()}`,
      ts: Date.now(),
      commandId: resumeCommandId,
      sessionId: streamId,
      type: 'session.attach',
      payload: { lastSeq: resumeSeq }
    });

    const resumeMessages = ws3.sentMessages.map((m: string) => JSON.parse(m));
    const resumeAcks = resumeMessages.filter(
      (m: any) => m.kind === 'ack' && m.commandId === resumeCommandId && m.payload?.state === 'resume'
    );
    assert.equal(resumeAcks.length, 1, 'Resume must receive exactly one resume ack frame');

    const resumeEvents = resumeMessages.filter((m: any) => m.kind === 'event' && m.sessionId === streamId);
    const resumeSeqs = resumeEvents.map((m: any) => m.seq);
    assert.equal(new Set(resumeSeqs).size, resumeSeqs.length, 'Resume replayed seqs must have NO duplicates');
    for (const s of resumeSeqs) {
      assert.ok(s > resumeSeq, `Replayed resume seq ${s} must be greater than lastSeq ${resumeSeq}`);
    }

    await ctx.sideManager.close(sideId, 'user');
  } finally {
    ctx.cleanup();
  }
});

test('SideConversationManager: bounds lastAttachWithoutCommandId to 1000 FIFO', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({ cwd: ctx.tmpBaseDir });
    const { sideId, streamId } = await ctx.sideManager.open({ parentSessionId: parentSession.id });

    const managerAny = ctx.sideManager as any;

    // Simulate 1005 attaches without commandId across different connections
    for (let i = 0; i < 1005; i++) {
      const fakeConn = { id: `conn_${i}`, attachedSessions: new Set<string>(), send: () => {} } as any;
      await ctx.sideManager.handleAttach(streamId, fakeConn, null);
    }

    assert.equal(managerAny.lastAttachWithoutCommandId.size, 1000, 'Cap must strictly be 1000');
    // First 5 (conn_0 .. conn_4) must have been evicted FIFO
    assert.equal(managerAny.lastAttachWithoutCommandId.has(`conn_0:${streamId}`), false);
    assert.equal(managerAny.lastAttachWithoutCommandId.has(`conn_4:${streamId}`), false);
    // The later ones must still be present
    assert.equal(managerAny.lastAttachWithoutCommandId.has(`conn_5:${streamId}`), true);
    assert.equal(managerAny.lastAttachWithoutCommandId.has(`conn_1004:${streamId}`), true);

    await ctx.sideManager.close(sideId, 'user');
  } finally {
    ctx.cleanup();
  }
});

test('SideConversationManager: purges lastAttachWithoutCommandId for connection on detach', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({ cwd: ctx.tmpBaseDir });
    const { sideId, streamId } = await ctx.sideManager.open({ parentSessionId: parentSession.id });

    const managerAny = ctx.sideManager as any;
    const testConn = { id: 'conn_detach_test', attachedSessions: new Set<string>(), send: () => {} } as any;

    await ctx.sideManager.handleAttach(streamId, testConn, null);
    assert.equal(managerAny.lastAttachWithoutCommandId.has(`conn_detach_test:${streamId}`), true);

    ctx.sideManager.handleDetach(streamId, testConn);
    assert.equal(
      managerAny.lastAttachWithoutCommandId.has(`conn_detach_test:${streamId}`),
      false,
      'Detach must purge lastAttachWithoutCommandId entry'
    );

    await ctx.sideManager.close(sideId, 'user');
  } finally {
    ctx.cleanup();
  }
});

test('SideConversationManager: purges lastAttachWithoutCommandId and processedAttachCommands on connection close', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({ cwd: ctx.tmpBaseDir });
    const { sideId, streamId } = await ctx.sideManager.open({ parentSessionId: parentSession.id });

    const managerAny = ctx.sideManager as any;
    const testConn = { id: 'conn_close_test', attachedSessions: new Set<string>(), send: () => {} } as any;

    // Attach with and without commandId
    await ctx.sideManager.handleAttach(streamId, testConn, null);
    await ctx.sideManager.handleAttach(streamId, testConn, null, 'cmd_123');

    assert.equal(managerAny.lastAttachWithoutCommandId.has(`conn_close_test:${streamId}`), true);
    assert.equal(managerAny.processedAttachCommands.has(`conn_close_test:${streamId}:cmd_123`), true);

    // Trigger connection close
    ctx.sideManager.handleConnectionClose(testConn);

    assert.equal(
      managerAny.lastAttachWithoutCommandId.has(`conn_close_test:${streamId}`),
      false,
      'Connection close must purge lastAttachWithoutCommandId'
    );
    assert.equal(
      managerAny.processedAttachCommands.has(`conn_close_test:${streamId}:cmd_123`),
      false,
      'Connection close must purge processedAttachCommands'
    );

    await ctx.sideManager.close(sideId, 'user');
  } finally {
    ctx.cleanup();
  }
});

test('SideConversationManager: connectionManager onClose automatically triggers handleConnectionClose', async () => {
  const ctx = createSideTestContext();
  try {
    const parentSession = await ctx.sessionRegistry.createSession({ cwd: ctx.tmpBaseDir });
    const { sideId, streamId } = await ctx.sideManager.open({ parentSessionId: parentSession.id });

    const managerAny = ctx.sideManager as any;
    await ctx.sideManager.handleAttach(streamId, ctx.conn, null);
    assert.equal(managerAny.lastAttachWithoutCommandId.has(`${ctx.conn.id}:${streamId}`), true);

    // Remove conn from ConnectionManager (which invokes closeListeners)
    ctx.connManager.remove(ctx.conn);

    assert.equal(
      managerAny.lastAttachWithoutCommandId.has(`${ctx.conn.id}:${streamId}`),
      false,
      'ConnectionManager remove must automatically trigger purge'
    );

    await ctx.sideManager.close(sideId, 'user');
  } finally {
    ctx.cleanup();
  }
});

