import type {
  PcpSnapshotPayload,
  SessionMeta,
  RuntimeMeta,
  TranscriptMeta
} from '@piframe/pcp-ts';

export interface SnapshotContext {
  sessionMeta: SessionMeta;
  runtimeStatus: string;
  model?: Record<string, unknown> | null;
  thinkingLevel?: string | null;
  steeringMode?: string | null;
  followUpMode?: string | null;
  isStreaming: boolean;
  runStartedAt?: number | null;
  isCompacting: boolean;
  autoCompaction: boolean;
  queue: {
    steering: string[];
    followUp: string[];
  };
  contextWindowOverride?: number | null;
  compactionReservePercent?: number;
  entries: Array<Record<string, unknown>>;
  pendingUiRequests: Array<Record<string, unknown>>;
  liveMessage?: Record<string, unknown> | null;
  activeTools?: Array<Record<string, unknown>>;
  usage?: Record<string, unknown>;
  workspace?: Record<string, unknown>;
}

export class SnapshotBuilder {
  public static readonly MAX_SNAPSHOT_ENTRIES = 100;
  public static readonly MAX_ENTRY_TEXT_BYTES = 256 * 1024; // 256 KB max text per field

  public static sanitizeEntry(entry: Record<string, unknown>): Record<string, unknown> {
    if (!entry || typeof entry !== 'object') return entry;
    let modified = false;
    const sanitized = { ...entry };
    if (typeof sanitized.text === 'string' && sanitized.text.length > SnapshotBuilder.MAX_ENTRY_TEXT_BYTES) {
      sanitized.text = sanitized.text.slice(0, SnapshotBuilder.MAX_ENTRY_TEXT_BYTES) + '\n\n... [truncated in snapshot for performance]';
      modified = true;
    }
    if (typeof sanitized.thinking === 'string' && sanitized.thinking.length > SnapshotBuilder.MAX_ENTRY_TEXT_BYTES) {
      sanitized.thinking = sanitized.thinking.slice(0, SnapshotBuilder.MAX_ENTRY_TEXT_BYTES) + '\n\n... [truncated in snapshot for performance]';
      modified = true;
    }
    return modified ? sanitized : entry;
  }

  public static build(ctx: SnapshotContext, seq?: number): PcpSnapshotPayload {
    const runtime: RuntimeMeta = {
      status: ctx.runtimeStatus,
      model: ctx.model ?? null,
      thinkingLevel: ctx.thinkingLevel ?? null,
      steeringMode: ctx.steeringMode ?? null,
      followUpMode: ctx.followUpMode ?? null,
      isStreaming: ctx.isStreaming,
      runStartedAt: ctx.runStartedAt ?? null,
      isCompacting: ctx.isCompacting,
      autoCompaction: ctx.autoCompaction,
      queue: ctx.queue,
      contextWindowOverride: ctx.contextWindowOverride ?? null,
      compactionReservePercent: ctx.compactionReservePercent ?? 2.5
    };

    const allEntries = ctx.entries ?? [];
    const boundedEntries = (
      allEntries.length > SnapshotBuilder.MAX_SNAPSHOT_ENTRIES
        ? allEntries.slice(-SnapshotBuilder.MAX_SNAPSHOT_ENTRIES)
        : allEntries
    ).map(SnapshotBuilder.sanitizeEntry);

    const transcript: TranscriptMeta = {
      entries: boundedEntries,
      leafId: null,
      totalEntries: allEntries.length,
      hasMore: allEntries.length > boundedEntries.length
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
