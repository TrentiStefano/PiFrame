import { isRecord, readProperty, type JsonRecord } from '../errors/errors.js';
import { PIFRAME_SUBAGENTS_STATUS_KEY, parseLiveSubagents, type LiveSubagentState } from './liveSubagents.js';
import { EventJournal } from '../journal/EventJournal.js';
import { SnapshotBuilder, type SnapshotContext } from '../journal/SnapshotBuilder.js';
import { adaptPiEvent, type SessionContext } from '../pi/PiEventAdapter.js';
import type { StdioPiTransport } from '../pi/StdioPiTransport.js';
import type { PcpEvent, PcpEventType, PcpSnapshotPayload, SessionMeta } from '@piframe/pcp-ts';
import type { PiEvent, PiModelInfo } from '../pi/piCommands.js';
import { UiRequestBroker } from '../ui/UiRequestBroker.js';
import { readContextPolicy, DEFAULT_COMPACTION_RESERVE_PERCENT } from '../pi/contextPolicy.js';

/**
 * The model as the snapshot protocol carries it. Pi reports either the model object or, when it
 * reported only an id (read back from the transcript), a bare string; the protocol's model is an
 * object, so a bare id is normalised to `{ id }`.
 */
export function snapshotModelOf(model: PiModelInfo | string | null | undefined): PiModelInfo | null {
  if (typeof model === 'string') return model ? { id: model } : null;
  return model ?? null;
}

export interface SessionOptions {
  id: string;
  name?: string;
  cwd: string;
  gitRoot?: string | null;
  sessionFile?: string | null;
  createdAt?: number;
  lastActivityAt?: number;
  onBroadcast?: (event: PcpEvent) => void;
}

/** A Pi or daemon event payload. Fields are narrowed where they are read. */
type EventPayload = JsonRecord;

/** The assistant message being streamed, before Pi reports it as complete. */
type LiveMessage = JsonRecord & { content: JsonRecord[] };

export class Session {
  public readonly id: string;
  public name?: string;
  public cwd: string;
  public gitRoot?: string | null;
  public sessionFile?: string | null;
  public forkSourceFile?: string;
  public readOnly = false;
  public readOnlyReason: 'terminal' | 'unknown' | null = null;
  public allowAmbiguousTerminal = false;
  public liveMessage: LiveMessage | null = null;
  /** Keyed by the Pi tool call id exactly as reported (a missing id is an undefined key, not the string "undefined"). */
  public activeTools = new Map<unknown, JsonRecord>();
  public usage: Record<string, unknown> = {};
  public createdAt: number;
  public lastActivityAt: number;

  public status: string = 'settled';
  public isStreaming: boolean = false;
  public runStartedAt: number | null = null;
  public isCompacting: boolean = false;
  /** Pi's estimate after the latest compaction; Pi reports context tokens as unknown until the next reply. */
  public postCompactionTokens?: number;
  public autoCompaction: boolean = true;
  public contextWindowOverride: number | null = null;
  public compactionReservePercent = DEFAULT_COMPACTION_RESERVE_PERCENT;
  /** Pi's model for the session; a bare model id when it was read back from the transcript. */
  public model: PiModelInfo | string | null | undefined = null;
  public thinkingLevel: string | null = 'medium';
  public steeringMode: string | null = 'one-at-a-time';
  public followUpMode: string | null = 'one-at-a-time';
  public queue = {
    steering: [] as string[],
    followUp: [] as string[]
  };

  public entries: Array<Record<string, unknown>> = [];
  public leafId: string | null = null;
  public workspace: Record<string, unknown> = {
    branch: null,
    dirty: false,
    changedFiles: 0,
    diffStat: '+0 -0'
  };

  public journal: EventJournal;
  public worker?: StdioPiTransport;
  /** Last report of PiFrame's subagent bridge in the current worker. */
  public liveSubagents: LiveSubagentState | null = null;
  /** When PiFrame's worker for this session last went away (stopped or crashed). */
  public workerGoneAt: number | null = null;
  public attachedClientIds = new Set<string>();
  public uiBroker: UiRequestBroker;

  private onBroadcast?: (event: PcpEvent) => void;
  private adapterContext: SessionContext;

  constructor(opts: SessionOptions) {
    this.id = opts.id;
    Object.assign(this, readContextPolicy(this.id));
    this.name = opts.name || opts.id;
    this.cwd = opts.cwd;
    this.gitRoot = opts.gitRoot;
    this.sessionFile = opts.sessionFile;
    this.createdAt = opts.createdAt || Date.now();
    this.lastActivityAt = opts.lastActivityAt ?? this.createdAt;
    this.onBroadcast = opts.onBroadcast;

    this.adapterContext = {
      sessionId: this.id
    };

    this.journal = new EventJournal({
      sessionId: this.id,
      getContext: () => this.getSnapshotContext()
    });

    this.uiBroker = new UiRequestBroker({
      sessionId: this.id,
      onEmitEvent: (evt) => {
        this.emitCustomEvent(evt.type, evt.payload);
      }
    });
  }

  public getSessionMeta(): SessionMeta {
    return {
      id: this.id,
      name: this.name,
      cwd: this.cwd,
      gitRoot: this.gitRoot,
      sessionFile: this.sessionFile,
      createdAt: this.createdAt,
      lastActivityAt: this.lastActivityAt,
      readOnly: this.readOnly,
      readOnlyReason: this.readOnlyReason
    } as SessionMeta;
  }

  public getSnapshotContext(): SnapshotContext {
    return {
      sessionMeta: this.getSessionMeta(),
      runtimeStatus: this.status,
      model: snapshotModelOf(this.model),
      thinkingLevel: this.thinkingLevel,
      steeringMode: this.steeringMode,
      followUpMode: this.followUpMode,
      isStreaming: this.isStreaming,
      runStartedAt: this.runStartedAt,
      isCompacting: this.isCompacting,
      autoCompaction: this.autoCompaction,
      contextWindowOverride: this.contextWindowOverride,
      compactionReservePercent: this.compactionReservePercent,
      queue: this.queue,
      entries: this.entries,
      pendingUiRequests: this.uiBroker.getPending(),
      liveMessage: this.liveMessage,
      activeTools: Array.from(this.activeTools.values()),
      usage: this.usage,
      workspace: this.workspace
    };
  }

  public getSnapshot(seq?: number): PcpSnapshotPayload {
    return SnapshotBuilder.build(this.getSnapshotContext(), seq ?? this.journal.currentSeq);
  }

  public reconcileEntries(newEntries: Array<Record<string, unknown>>, leafId?: string | null): void {
    if (leafId !== undefined) {
      this.leafId = leafId;
    }
    if (!newEntries || newEntries.length === 0) return;

    const existingIds = new Set(this.entries.map((e) => e.id || e.entryId).filter(Boolean));
    for (const entry of newEntries) {
      const id = entry.id || entry.entryId;
      if (!id || !existingIds.has(id)) {
        this.entries.push(entry);
        if (id) existingIds.add(id);
      }
    }
  }

  public dispatchPiEvent(rawEvent: PiEvent): PcpEvent[] {
    // The subagent bridge reports through a reserved status key: keep it as
    // live state, never as a visible status line or a journal event.
    if (
      rawEvent.type === 'extension_ui_request' &&
      rawEvent.method === 'setStatus' &&
      rawEvent.statusKey === PIFRAME_SUBAGENTS_STATUS_KEY
    ) {
      const live = parseLiveSubagents(rawEvent.statusText);
      if (live) this.liveSubagents = live;
      return [];
    }
    this.lastActivityAt = Date.now();
    const adapted = adaptPiEvent(rawEvent, this.adapterContext);
    const emitted: PcpEvent[] = [];

    for (const item of adapted) {
      this.updateInternalState(item.type, item.payload);
      const pcpEvent = this.journal.append(item);
      emitted.push(pcpEvent);

      if (this.onBroadcast) {
        this.onBroadcast(pcpEvent);
      }
    }

    return emitted;
  }

  /** A new worker starts: its bridge reports afresh. */
  public markWorkerStarted(): void {
    this.liveSubagents = null;
    this.workerGoneAt = null;
  }

  /** The worker is gone, and the background agents running inside it with it. */
  public markWorkerGone(at = Date.now()): void {
    this.liveSubagents = null;
    this.workerGoneAt = at;
  }

  /** Whether a background agent is running in this session's worker. */
  public get hasRunningSubagents(): boolean {
    return this.liveSubagents?.anyRunning === true;
  }

  public emitCustomEvent(type: PcpEventType, payload: EventPayload): PcpEvent {
    this.lastActivityAt = Date.now();
    this.updateInternalState(type, payload);
    const event = this.journal.append({ type, payload });
    if (this.onBroadcast) {
      this.onBroadcast(event);
    }
    return event;
  }

  private settleRun(): void {
    this.finishActiveTools();
    this.status = 'settled';
    this.runStartedAt = null;
    this.isStreaming = false;
    this.liveMessage = null;
    this.activeTools.clear();
  }

  private recordToolTiming(tool: JsonRecord): void {
    for (let i = this.entries.length - 1; i >= 0; i--) {
      const entry = this.entries[i];
      if (!entry) continue;
      const message: unknown = entry.message || entry;
      if (!isRecord(message)) continue;
      for (const calls of [message.toolCalls, message.content]) {
        if (!Array.isArray(calls)) continue;
        const list: unknown[] = calls;
        const call = list.find(
          (c): c is Record<string, unknown> => isRecord(c) && (c.id ?? c.toolCallId) === tool.toolCallId
        );
        if (!call) continue;
        if (tool.startedAt != null) call.startedAt = tool.startedAt;
        if (tool.durationMs != null) call.durationMs = tool.durationMs;
        return;
      }
    }
  }

  private finishActiveTools(): void {
    for (const tool of this.activeTools.values()) {
      if (tool.isRunning) {
        tool.isRunning = false;
        if (tool.startedAt != null) tool.durationMs ??= Math.max(0, this.lastActivityAt - Number(tool.startedAt));
      }
      this.recordToolTiming(tool);
    }
  }

  private updateInternalState(type: PcpEventType, payload: EventPayload): void {
    switch (type) {
      case 'message.started':
        this.liveMessage = { id: payload.messageId, role: payload.role, content: [] };
        break;

      case 'text.delta':
      case 'thinking.delta': {
        const live: LiveMessage = (this.liveMessage ??= { role: 'assistant', content: [] });
        const index = Number(payload.contentIndex) || 0;
        const field = type === 'text.delta' ? 'text' : 'thinking';
        const block: JsonRecord = live.content[index] || { type: field, [field]: '' };
        block[field] = String(block[field]) + String(payload.delta || '');
        live.content[index] = block;
        break;
      }

      case 'tool.started': {
        const toolKey = payload.toolCallId;
        payload.startedAt ??= this.activeTools.get(toolKey)?.startedAt ?? this.lastActivityAt;
        this.activeTools.set(toolKey, { ...payload, isRunning: true });
        this.recordToolTiming(payload);
        break;
      }
      case 'tool.progress': {
        const toolKey = payload.toolCallId;
        const tool = this.activeTools.get(toolKey) || {};
        this.activeTools.set(toolKey, { ...tool, ...payload, output: payload.partialResult });
        break;
      }
      case 'tool.completed': {
        const toolKey = payload.toolCallId;
        const tool = this.activeTools.get(toolKey) || {};
        if (payload.durationMs == null && tool.startedAt != null) {
          payload.durationMs = Math.max(0, this.lastActivityAt - Number(tool.startedAt));
        }
        const completed = { ...tool, ...payload, output: payload.result, isRunning: false };
        this.activeTools.set(toolKey, completed);
        this.recordToolTiming(completed);
        break;
      }
      case 'usage.updated': {
        const usage = payload.usage;
        this.usage = isRecord(usage) ? usage : {};
        break;
      }
      case 'run.started':
        payload.startedAt ??= this.lastActivityAt;
        this.runStartedAt = typeof payload.startedAt === 'number' ? payload.startedAt : null;
        this.status = 'working';
        this.isStreaming = true;
        break;

      case 'run.ended':
        this.isStreaming = false;
        if (payload.willRetry) {
          this.status = 'retrying';
        }
        break;

      case 'session.status':
        // Recovery must settle the same execution state as a normal stop.
        if (payload.status === 'settled' || payload.status === 'idle') {
          this.settleRun();
        }
        break;

      case 'run.settled':
        this.settleRun();
        break;

      case 'retry.started':
        this.status = 'retrying';
        break;

      case 'compaction.started':
        this.status = 'compacting';
        this.isCompacting = true;
        break;

      case 'compaction.ended':
        this.isCompacting = false;
        if (!payload.aborted && payload.result) {
          const tokensAfter = readProperty(payload.result, 'estimatedTokensAfter');
          this.postCompactionTokens = typeof tokensAfter === 'number' ? tokensAfter : undefined;
        }
        this.status = this.isStreaming ? 'working' : 'settled';
        break;

      case 'queue.changed':
        this.queue = {
          steering: Array.isArray(payload.steering) ? payload.steering : [],
          followUp: Array.isArray(payload.followUp) ? payload.followUp : []
        };
        break;

      case 'ui.request':
        this.uiBroker.addRequest(payload);
        if (payload.dialog) {
          this.status = 'awaiting_user';
        }
        break;

      case 'ui.resolved':
        if (this.status === 'awaiting_user') {
          this.status = this.isStreaming ? 'working' : 'settled';
        }
        break;

      case 'message.completed': {
        this.liveMessage = null;
        this.activeTools.clear();
        const message = payload.message;
        if (isRecord(message) && message.role !== 'system') {
          this.entries.push(message);
          if (message.id) {
            this.leafId = String(message.id);
          }
        }
        break;
      }

      case 'worker.crashed':
        this.finishActiveTools();
        this.runStartedAt = null;
        this.uiBroker.cancelAll('worker_crashed');
        this.status = 'worker_error';
        this.isStreaming = false;
        break;

      // Events this state does not track: they leave the session state unchanged.
      case 'bash.output':
      case 'daemon.configChanged':
      case 'extension.error':
      case 'journal.gap':
      case 'remote.statusChanged':
      case 'retry.ended':
      case 'session.indexChanged':
      case 'side.closed':
      case 'side.opened':
      case 'summarization.retry':
      case 'system.metrics':
      case 'text.completed':
      case 'text.started':
      case 'thinking.completed':
      case 'thinking.started':
      case 'toolcall.argsDelta':
      case 'toolcall.completed':
      case 'toolcall.started':
      case 'turn.ended':
      case 'turn.started':
      case 'ui.claimed':
      case 'ui.editorText':
      case 'ui.notify':
      case 'ui.status':
      case 'ui.title':
      case 'ui.widget':
      case 'worker.diagnostic':
      case 'workspace.changed':
        break;
    }
  }

  public close(): Promise<void> {
    this.uiBroker.dispose();
    return this.journal.close();
  }
}
