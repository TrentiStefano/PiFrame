import * as path from 'node:path';
import { EventJournal } from '../journal/EventJournal.js';
import { SnapshotBuilder, type SnapshotContext } from '../journal/SnapshotBuilder.js';
import { adaptPiEvent, type SessionContext } from '../pi/PiEventAdapter.js';
import type { StdioPiTransport } from '../pi/StdioPiTransport.js';
import type { PcpEvent, PcpEventType, PcpSnapshotPayload, SessionMeta } from '@pi-crust/pcp-ts';
import type { PiEvent } from '../pi/piCommands.js';
import { UiRequestBroker } from '../ui/UiRequestBroker.js';

export interface SessionOptions {
  id: string;
  name?: string;
  cwd: string;
  gitRoot?: string | null;
  sessionFile?: string | null;
  createdAt?: number;
  onBroadcast?: (event: PcpEvent) => void;
}

export class Session {
  public readonly id: string;
  public name?: string;
  public cwd: string;
  public gitRoot?: string | null;
  public sessionFile?: string | null;
  public createdAt: number;
  public lastActivityAt: number;

  public status: string = 'settled';
  public isStreaming: boolean = false;
  public isCompacting: boolean = false;
  public autoCompaction: boolean = true;
  public model: any = null;
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
  public attachedClientIds = new Set<string>();
  public uiBroker: UiRequestBroker;

  private onBroadcast?: (event: PcpEvent) => void;
  private adapterContext: SessionContext;

  constructor(opts: SessionOptions) {
    this.id = opts.id;
    this.name = opts.name || opts.id;
    this.cwd = opts.cwd;
    this.gitRoot = opts.gitRoot;
    this.sessionFile = opts.sessionFile;
    this.createdAt = opts.createdAt || Date.now();
    this.lastActivityAt = this.createdAt;
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
        this.emitCustomEvent(evt.type as any, evt.payload);
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
      lastActivityAt: this.lastActivityAt
    };
  }

  public getSnapshotContext(): SnapshotContext {
    return {
      sessionMeta: this.getSessionMeta(),
      runtimeStatus: this.status,
      model: this.model,
      thinkingLevel: this.thinkingLevel,
      steeringMode: this.steeringMode,
      followUpMode: this.followUpMode,
      isStreaming: this.isStreaming,
      isCompacting: this.isCompacting,
      autoCompaction: this.autoCompaction,
      queue: this.queue,
      entries: this.entries,
      pendingUiRequests: this.uiBroker.getPending(),
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

    const existingIds = new Set(this.entries.map((e: any) => e.id || e.entryId).filter(Boolean));
    for (const entry of newEntries) {
      const id = (entry as any).id || (entry as any).entryId;
      if (!id || !existingIds.has(id)) {
        this.entries.push(entry);
        if (id) existingIds.add(id);
      }
    }
  }

  public dispatchPiEvent(rawEvent: PiEvent): PcpEvent[] {
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

  public emitCustomEvent(type: PcpEventType, payload: any): PcpEvent {
    this.lastActivityAt = Date.now();
    this.updateInternalState(type, payload);
    const event = this.journal.append({ type, payload });
    if (this.onBroadcast) {
      this.onBroadcast(event);
    }
    return event;
  }

  private updateInternalState(type: PcpEventType, payload: any): void {
    switch (type) {
      case 'run.started':
        this.status = 'working';
        this.isStreaming = true;
        break;

      case 'run.ended':
        this.isStreaming = false;
        if (payload.willRetry) {
          this.status = 'retrying';
        }
        break;

      case 'run.settled':
        this.status = 'settled';
        this.isStreaming = false;
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
        this.status = this.isStreaming ? 'working' : 'settled';
        break;

      case 'queue.changed':
        this.queue = {
          steering: payload.steering || [],
          followUp: payload.followUp || []
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

      case 'message.completed':
        if (payload.message) {
          this.entries.push(payload.message);
          if (payload.message.id) {
            this.leafId = payload.message.id;
          }
        }
        break;

      case 'worker.crashed':
        this.uiBroker.cancelAll('worker_crashed');
        this.status = 'worker_error';
        this.isStreaming = false;
        break;
    }
  }

  public close(): void {
    this.uiBroker.dispose();
    this.journal.close();
  }
}
