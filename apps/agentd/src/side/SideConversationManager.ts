import * as fs from 'node:fs';
import * as path from 'node:path';
import { ulid } from 'ulid';
import { getPiFrameBaseDir } from '../config/config.js';
import { StdioPiTransport } from '../pi/StdioPiTransport.js';
import type { PiTransport } from '../pi/PiTransport.js';
import type { PiCapabilities } from '../pi/piCommands.js';
import { adaptPiEvent } from '../pi/PiEventAdapter.js';
import type { ConnectionManager } from '../server/wsServer.js';
import type { Connection } from '../server/connection.js';
import type { SessionRegistry } from '../sessions/SessionRegistry.js';
import type { Session } from '../sessions/Session.js';
import type { PcpEvent } from '@piframe/pcp-ts';
import { SideTransport } from './SideTransport.js';
import {
  renderConversationSnapshot,
  writeSideContextFile,
  cleanupSideContextDir,
  cleanStaleSideDirs,
  DEFAULT_MAX_SNAPSHOT_CHARS
} from './SideSnapshotRenderer.js';

export const ALLOWED_SIDE_TOOLS = new Set(['read', 'grep', 'find', 'ls']);
export const DEFAULT_SIDE_IDLE_TIMEOUT_MS = 10 * 60 * 1000; // 10 minutes
export const MAX_CONCURRENT_SIDE_THREADS = 4;
export const MAX_SIDE_EVENTS_BUFFER = 1000;

export interface SideConversationManagerOptions {
  piExecutablePath: string;
  capabilities?: PiCapabilities;
  connectionManager: ConnectionManager;
  sessionRegistry: SessionRegistry;
  defaultIdleTimeoutMs?: number;
  baseDir?: string;
  maxConversations?: number;
  maxSnapshotChars?: number;
  transportFactory?: (opts: { executablePath: string; capabilities?: PiCapabilities }) => PiTransport;
}

export type SideCloseReason = 'user' | 'idle' | 'parentClosed' | 'error' | 'shutdown';

export interface SideThread {
  sideId: string;
  streamId: string;
  parentSessionId: string;
  cwd: string;
  worker: SideTransport;
  rawWorker: PiTransport;
  contextDir: string;
  contextFilePath: string;
  eventsBuffer: PcpEvent[];
  currentSeq: number;
  idleTimer: NodeJS.Timeout | null;
  idleTimeoutMs: number;
  attachedClientIds: Set<string>;
  closed: boolean;
  model: any;
  pumpPromise?: Promise<void>;
}

export class SideConversationManager {
  private piExecutablePath: string;
  private capabilities: PiCapabilities;
  private connectionManager: ConnectionManager;
  private sessionRegistry: SessionRegistry;
  private idleTimeoutMs: number;
  private baseDir: string;
  private maxConversations: number;
  private maxSnapshotChars: number;
  private transportFactory?: (opts: { executablePath: string; capabilities?: PiCapabilities }) => PiTransport;

  private threads = new Map<string, SideThread>(); // sideId -> SideThread
  private threadsByParent = new Map<string, SideThread>(); // parentSessionId -> SideThread
  private shuttingDown = false;
  private processedAttachCommands = new Set<string>();
  private lastAttachWithoutCommandId = new Map<string, number>();

  constructor(opts: SideConversationManagerOptions) {
    this.piExecutablePath = opts.piExecutablePath;
    this.capabilities = opts.capabilities ?? {
      version: '0.85.1',
      supported: true,
      modes: ['rpc'],
      features: ['thinking', 'tools']
    };
    this.connectionManager = opts.connectionManager;
    this.sessionRegistry = opts.sessionRegistry;
    this.idleTimeoutMs = opts.defaultIdleTimeoutMs ?? DEFAULT_SIDE_IDLE_TIMEOUT_MS;
    this.baseDir = opts.baseDir ?? getPiFrameBaseDir();
    cleanStaleSideDirs(this.baseDir);
    this.maxConversations = opts.maxConversations ?? MAX_CONCURRENT_SIDE_THREADS;
    this.maxSnapshotChars = opts.maxSnapshotChars ?? DEFAULT_MAX_SNAPSHOT_CHARS;
    this.transportFactory = opts.transportFactory;

    if (typeof this.sessionRegistry?.setSessionClosedCallback === 'function') {
      this.sessionRegistry.setSessionClosedCallback(async (sessionId) => {
        await this.onParentSessionClosed(sessionId).catch((err) => {
          console.error(`[SideConversationManager] onParentSessionClosed error:`, err);
        });
      });
    }

    if (typeof this.connectionManager?.onClose === 'function') {
      this.connectionManager.onClose((conn) => {
        this.handleConnectionClose(conn);
      });
    }
  }

  public hasStream(streamId: string): boolean {
    return Array.from(this.threads.values()).some((t) => t.streamId === streamId && !t.closed);
  }

  public getSideByStreamId(streamId: string): SideThread | undefined {
    return Array.from(this.threads.values()).find((t) => t.streamId === streamId);
  }

  public getSide(sideId: string): SideThread | undefined {
    return this.threads.get(sideId);
  }

  public getActiveCount(): number {
    return this.threads.size;
  }

  public async open(opts: {
    parentSessionId: string;
    question?: string;
    conn?: Connection;
  }): Promise<{ sideId: string; streamId: string }> {
    if (this.shuttingDown) {
      throw new Error('Daemon is shutting down');
    }

    const parentSession = this.sessionRegistry.getSession(opts.parentSessionId);
    if (!parentSession) {
      const err = new Error(`Parent session ${opts.parentSessionId} not found`);
      (err as any).code = 'SESSION_NOT_FOUND';
      throw err;
    }

    // 1. One open side thread per parent session: return existing if active
    const existing = this.threadsByParent.get(opts.parentSessionId);
    if (existing && !existing.closed) {
      if (opts.conn) {
        opts.conn.attachedSessions.add(existing.streamId);
        existing.attachedClientIds.add(opts.conn.id);
      }
      this.touch(existing.sideId);
      if (opts.question && opts.question.trim().length > 0) {
        void this.prompt(existing.sideId, opts.question).catch(async (err) => {
          console.error(`[SideConversationManager] Auto-prompt failed for ${existing.sideId}:`, err);
          const t = this.threads.get(existing.sideId);
          if (t && !t.closed) {
            this.emitDiagnostic(t, err?.message || String(err), 'error');
            await this.close(existing.sideId, 'error').catch(() => {});
          }
        });
      }
      return { sideId: existing.sideId, streamId: existing.streamId };
    }

    // 2. Max 4 total side threads limit
    if (this.threads.size >= this.maxConversations) {
      const err = new Error(`Maximum concurrent side conversations (${this.maxConversations}) reached`);
      (err as any).code = 'SIDE_LIMIT_REACHED';
      throw err;
    }

    const sideId = `side_${ulid()}`;
    const streamId = sideId;

    // 3. Obtain conversation messages for snapshot
    let messages: any[] = [];
    if (parentSession.worker && parentSession.worker.health().alive) {
      try {
        const res = await parentSession.worker.send({ command: 'get_messages' });
        if (res && res.data && Array.isArray(res.data.messages)) {
          messages = res.data.messages;
        }
      } catch {
        // Fallback to daemon-side session transcript entries
        messages = parentSession.entries || [];
      }
    } else {
      messages = parentSession.entries || [];
    }

    // 4. Render snapshot markdown and write to ~/.piframe/runtime/side/<sideId>/context.md
    const snapshotText = renderConversationSnapshot({
      messages,
      maxChars: this.maxSnapshotChars
    });

    const contextFilePath = writeSideContextFile(this.baseDir, sideId, snapshotText);
    const contextDir = path.dirname(contextFilePath);

    // 5. Build worker spawn args
    // Flags: ['--mode','rpc','--no-session','--tools','read,grep,find,ls','--no-mcp','--no-extensions','--no-skills','--append-system-prompt', <tempfile>, '--model', <model>, '--thinking', <thinking>]
    const args = [
      '--mode',
      'rpc',
      '--no-session',
      '--tools',
      'read,grep,find,ls',
      '--no-mcp',
      '--no-extensions',
      '--no-skills',
      '--append-system-prompt',
      contextFilePath
    ];

    if (parentSession.model) {
      const m = parentSession.model;
      const modelPattern = typeof m === 'string'
        ? m
        : (m.provider && m.id ? `${m.provider}/${m.id}` : (m.id || String(m)));
      args.push('--model', modelPattern);
    }

    if (parentSession.thinkingLevel) {
      args.push('--thinking', parentSession.thinkingLevel);
    }

    // 6. Spawn worker (context-limit extension is NOT loaded)
    const rawWorker = this.transportFactory
      ? this.transportFactory({ executablePath: this.piExecutablePath, capabilities: this.capabilities })
      : new StdioPiTransport({ executablePath: this.piExecutablePath, capabilities: this.capabilities });

    try {
      await rawWorker.start({
        cwd: parentSession.cwd,
        args
      });
    } catch (startErr) {
      cleanupSideContextDir(this.baseDir, sideId);
      throw startErr;
    }

    const worker = new SideTransport(rawWorker);

    // 7. Verify active tools if exposed via get_state
    let stateData: any;
    try {
      const stateRes = await worker.send({ command: 'get_state' });
      stateData = stateRes?.data;
      const exposedTools = stateData?.tools || stateData?.activeTools;
      if (Array.isArray(exposedTools)) {
        for (const t of exposedTools) {
          const name = typeof t === 'string' ? t : t?.name;
          if (name && !ALLOWED_SIDE_TOOLS.has(name)) {
            await rawWorker.stop({ graceMs: 500 });
            cleanupSideContextDir(this.baseDir, sideId);
            const err = new Error(`Unsafe tool "${name}" exposed to side conversation`);
            (err as any).code = 'SIDE_UNSAFE_TOOLS';
            throw err;
          }
        }
      }
    } catch (checkErr: any) {
      if (checkErr?.code === 'SIDE_UNSAFE_TOOLS') {
        throw checkErr;
      }
      // If get_state failed for other reasons, abort
      await rawWorker.stop({ graceMs: 500 });
      cleanupSideContextDir(this.baseDir, sideId);
      throw checkErr;
    }

    // 8. Construct SideThread
    const thread: SideThread = {
      sideId,
      streamId,
      parentSessionId: opts.parentSessionId,
      cwd: parentSession.cwd,
      worker,
      rawWorker,
      contextDir,
      contextFilePath,
      eventsBuffer: [],
      currentSeq: 0,
      idleTimer: null,
      idleTimeoutMs: this.idleTimeoutMs,
      attachedClientIds: new Set<string>(),
      closed: false,
      model: stateData?.model || parentSession.model || null
    };

    if (opts.conn) {
      opts.conn.attachedSessions.add(streamId);
      thread.attachedClientIds.add(opts.conn.id);
    }

    this.threads.set(sideId, thread);
    this.threadsByParent.set(opts.parentSessionId, thread);

    // 9. Start background event pumping
    thread.pumpPromise = this.pumpSideEvents(thread).catch((err) => {
      console.error(`[SideConversationManager] pumpSideEvents failed for ${thread.sideId}:`, err);
    });

    // 10. Emit side.opened event on streamId
    thread.currentSeq++;
    const openedEvt: PcpEvent = {
      protocol: 1,
      kind: 'event',
      id: `evt_${ulid()}`,
      ts: Date.now(),
      sessionId: streamId,
      seq: thread.currentSeq,
      type: 'side.opened',
      payload: {
        sideId,
        parentSessionId: opts.parentSessionId,
        model: thread.model
      }
    };
    this.pushEvent(thread, openedEvt);
    this.connectionManager.broadcast(streamId, openedEvt);

    // 11. Schedule idle timeout
    this.scheduleIdleTimeout(sideId);

    // 12. If question provided, prompt side worker
    if (opts.question && opts.question.trim().length > 0) {
      void this.prompt(sideId, opts.question).catch(async (err) => {
        console.error(`[SideConversationManager] Auto-prompt failed for ${sideId}:`, err);
        const t = this.threads.get(sideId);
        if (t && !t.closed) {
          this.emitDiagnostic(t, err?.message || String(err), 'error');
          await this.close(sideId, 'error').catch(() => {});
        }
      });
    }

    return { sideId, streamId };
  }

  public async prompt(sideId: string, text: string): Promise<{ prompted: true }> {
    const thread = this.threads.get(sideId);
    if (!thread || thread.closed) {
      const err = new Error(`Side conversation ${sideId} not found`);
      (err as any).code = 'SIDE_NOT_FOUND';
      throw err;
    }

    this.touch(sideId);
    await thread.worker.send({ command: 'prompt', message: text });
    return { prompted: true };
  }

  public async abort(sideId: string): Promise<{ aborted: true }> {
    const thread = this.threads.get(sideId);
    if (!thread || thread.closed) {
      const err = new Error(`Side conversation ${sideId} not found`);
      (err as any).code = 'SIDE_NOT_FOUND';
      throw err;
    }

    this.touch(sideId);
    await thread.worker.send({ command: 'abort' });
    return { aborted: true };
  }

  public async close(sideId: string, reason: SideCloseReason = 'user'): Promise<{ closed: true }> {
    const thread = this.threads.get(sideId);
    if (!thread || thread.closed) {
      const err = new Error(`Side conversation ${sideId} not found`);
      (err as any).code = 'SIDE_NOT_FOUND';
      throw err;
    }

    thread.closed = true;

    if (thread.idleTimer) {
      clearTimeout(thread.idleTimer);
      thread.idleTimer = null;
    }

    // Emit side.closed event
    thread.currentSeq++;
    const closedEvt: PcpEvent = {
      protocol: 1,
      kind: 'event',
      id: `evt_${ulid()}`,
      ts: Date.now(),
      sessionId: thread.streamId,
      seq: thread.currentSeq,
      type: 'side.closed',
      payload: {
        sideId,
        reason
      }
    };
    this.pushEvent(thread, closedEvt);
    this.connectionManager.broadcast(thread.streamId, closedEvt);

    // Stop worker process
    try {
      await thread.rawWorker.stop({ graceMs: 1000 });
    } catch {
      // Ignore stop error
    }

    // Delete temp runtime directory
    cleanupSideContextDir(this.baseDir, sideId);

    // Remove from active maps
    this.threads.delete(sideId);
    if (this.threadsByParent.get(thread.parentSessionId) === thread) {
      this.threadsByParent.delete(thread.parentSessionId);
    }

    return { closed: true };
  }

  public async onParentSessionClosed(parentSessionId: string): Promise<void> {
    const thread = this.threadsByParent.get(parentSessionId);
    if (thread && !thread.closed) {
      await this.close(thread.sideId, 'parentClosed').catch(() => {});
    }
  }

  public async handleAttach(
    streamId: string,
    conn: Connection,
    lastSeq?: number | null,
    commandId?: string
  ): Promise<void> {
    const thread = this.getSideByStreamId(streamId);
    if (!thread) {
      const err = new Error(`Side conversation stream ${streamId} not found`);
      (err as any).code = 'SIDE_NOT_FOUND';
      throw err;
    }

    if (commandId) {
      const attachKey = `${conn.id}:${streamId}:${commandId}`;
      if (this.processedAttachCommands.has(attachKey)) {
        return;
      }
      this.processedAttachCommands.add(attachKey);
      if (this.processedAttachCommands.size > 1000) {
        const first = this.processedAttachCommands.values().next().value;
        if (first) this.processedAttachCommands.delete(first);
      }
    } else {
      const fallbackKey = `${conn.id}:${streamId}`;
      const lastTime = this.lastAttachWithoutCommandId.get(fallbackKey);
      const now = Date.now();
      if (lastTime && now - lastTime < 500) {
        return;
      }
      if (this.lastAttachWithoutCommandId.has(fallbackKey)) {
        this.lastAttachWithoutCommandId.delete(fallbackKey);
      }
      this.lastAttachWithoutCommandId.set(fallbackKey, now);
      while (this.lastAttachWithoutCommandId.size > 1000) {
        const oldest = this.lastAttachWithoutCommandId.keys().next().value;
        if (oldest === undefined) break;
        this.lastAttachWithoutCommandId.delete(oldest);
      }
    }

    conn.attachedSessions.add(streamId);
    thread.attachedClientIds.add(conn.id);

    if (lastSeq === null || lastSeq === undefined) {
      // Full replay of buffered events
      conn.send({
        protocol: 1,
        kind: 'ack',
        id: `ack_${ulid()}`,
        ts: Date.now(),
        commandId: commandId || `att_${ulid()}`,
        type: 'command.ack',
        sessionId: streamId,
        payload: { state: 'snapshot' }
      } as any);

      for (const evt of thread.eventsBuffer) {
        conn.send(evt);
      }
    } else {
      // Resume from lastSeq
      conn.send({
        protocol: 1,
        kind: 'ack',
        id: `ack_${ulid()}`,
        ts: Date.now(),
        commandId: commandId || `att_${ulid()}`,
        type: 'command.ack',
        sessionId: streamId,
        payload: { state: 'resume' }
      } as any);

      for (const evt of thread.eventsBuffer) {
        if (evt.seq > lastSeq) {
          conn.send(evt);
        }
      }
    }
  }

  public handleDetach(streamId: string, conn: Connection): void {
    conn.attachedSessions.delete(streamId);
    const thread = this.getSideByStreamId(streamId);
    if (thread) {
      thread.attachedClientIds.delete(conn.id);
    }
    const fallbackKey = `${conn.id}:${streamId}`;
    this.lastAttachWithoutCommandId.delete(fallbackKey);
  }

  public handleConnectionClose(conn: Connection | string): void {
    const connId = typeof conn === 'string' ? conn : conn.id;
    for (const key of Array.from(this.lastAttachWithoutCommandId.keys())) {
      if (key.startsWith(`${connId}:`)) {
        this.lastAttachWithoutCommandId.delete(key);
      }
    }
    for (const key of Array.from(this.processedAttachCommands.keys())) {
      if (key.startsWith(`${connId}:`)) {
        this.processedAttachCommands.delete(key);
      }
    }
    for (const thread of this.threads.values()) {
      thread.attachedClientIds.delete(connId);
    }
  }

  public touch(sideId: string): void {
    const thread = this.threads.get(sideId);
    if (!thread || thread.closed) return;
    if (thread.idleTimer) {
      clearTimeout(thread.idleTimer);
      thread.idleTimer = null;
    }
    this.scheduleIdleTimeout(sideId);
  }

  private scheduleIdleTimeout(sideId: string): void {
    const thread = this.threads.get(sideId);
    if (!thread || thread.closed) return;
    if (thread.idleTimeoutMs <= 0) return;

    thread.idleTimer = setTimeout(() => {
      void this.close(sideId, 'idle').catch((err) => {
        console.error(`[SideConversationManager] Idle close error for ${sideId}:`, err);
      });
    }, thread.idleTimeoutMs);
  }

  private emitDiagnostic(thread: SideThread, message: string, level: 'error' | 'warn' | 'info' = 'error'): void {
    if (thread.closed) return;
    thread.currentSeq++;
    const diagEvt: PcpEvent = {
      protocol: 1,
      kind: 'event',
      id: `evt_${ulid()}`,
      ts: Date.now(),
      sessionId: thread.streamId,
      seq: thread.currentSeq,
      type: 'worker.diagnostic',
      payload: {
        level,
        message,
        source: 'sideManager'
      }
    };
    this.pushEvent(thread, diagEvt);
    this.connectionManager.broadcast(thread.streamId, diagEvt);
  }

  private pushEvent(thread: SideThread, event: PcpEvent): void {
    thread.eventsBuffer.push(event);
    if (thread.eventsBuffer.length > MAX_SIDE_EVENTS_BUFFER) {
      thread.eventsBuffer.shift();
    }
  }

  private async pumpSideEvents(thread: SideThread): Promise<void> {
    try {
      for await (const rawEvent of thread.worker.events()) {
        if (thread.closed) break;
        this.touch(thread.sideId);
        const adapted = adaptPiEvent(rawEvent, { sessionId: thread.streamId });
        for (const item of adapted) {
          thread.currentSeq++;
          const pcpEvent: PcpEvent = {
            protocol: 1,
            kind: 'event',
            id: `evt_${ulid()}`,
            ts: Date.now(),
            sessionId: thread.streamId,
            seq: thread.currentSeq,
            type: item.type,
            payload: item.payload
          };
          this.pushEvent(thread, pcpEvent);
          this.connectionManager.broadcast(thread.streamId, pcpEvent);
        }
      }
    } catch {
      if (!thread.closed) {
        await this.close(thread.sideId, 'error');
      }
    }
  }

  public async dispose(): Promise<void> {
    this.shuttingDown = true;
    const activeSideIds = Array.from(this.threads.keys());
    await Promise.all(activeSideIds.map((sid) => this.close(sid, 'shutdown').catch(() => {})));
  }
}
