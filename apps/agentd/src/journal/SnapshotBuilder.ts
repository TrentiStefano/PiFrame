import type {
  PcpSnapshotPayload,
  SessionMeta,
  RuntimeMeta,
  TranscriptMeta
} from '@pi-crust/pcp-ts';

export interface SnapshotContext {
  sessionMeta: SessionMeta;
  runtimeStatus: string;
  model?: Record<string, unknown> | null;
  thinkingLevel?: string | null;
  steeringMode?: string | null;
  followUpMode?: string | null;
  isStreaming: boolean;
  isCompacting: boolean;
  autoCompaction: boolean;
  queue: {
    steering: string[];
    followUp: string[];
  };
  entries: Array<Record<string, unknown>>;
  pendingUiRequests: Array<Record<string, unknown>>;
  liveMessage?: Record<string, unknown> | null;
  activeTools?: Array<Record<string, unknown>>;
  usage?: Record<string, unknown>;
  workspace?: Record<string, unknown>;
}

export class SnapshotBuilder {
  public static build(ctx: SnapshotContext, seq?: number): PcpSnapshotPayload {
    const runtime: RuntimeMeta = {
      status: ctx.runtimeStatus,
      model: ctx.model ?? null,
      thinkingLevel: ctx.thinkingLevel ?? null,
      steeringMode: ctx.steeringMode ?? null,
      followUpMode: ctx.followUpMode ?? null,
      isStreaming: ctx.isStreaming,
      isCompacting: ctx.isCompacting,
      autoCompaction: ctx.autoCompaction,
      queue: ctx.queue
    };

    const transcript: TranscriptMeta = {
      entries: ctx.entries,
      leafId: null
    };

    return {
      session: ctx.sessionMeta,
      runtime,
      transcript,
      liveMessage: ctx.liveMessage ?? null,
      activeTools: ctx.activeTools ?? [],
      pendingUiRequests: ctx.pendingUiRequests,
      usage: ctx.usage ?? {},
      workspace: ctx.workspace ?? {
        branch: null,
        dirty: false,
        changedFiles: 0,
        diffStat: '+0 -0'
      }
    };
  }
}
