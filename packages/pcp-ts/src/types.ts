/**
 * PCP/1 (PiFrame Protocol) TypeScript Type Definitions
 * Normative contract for client-daemon communication.
 */

export type ProtocolVersion = 1;

export type ProtocolKind =
  | 'hello'
  | 'welcome'
  | 'command'
  | 'ack'
  | 'result'
  | 'event'
  | 'snapshot'
  | 'error'
  | 'ping'
  | 'pong';

export interface PcpEnvelope<T = Record<string, unknown>> {
  protocol: ProtocolVersion;
  kind: ProtocolKind;
  id: string;
  ts: number;
  commandId?: string;
  sessionId?: string;
  seq?: number;
  type: string;
  payload: T;
}

// -----------------------------------------------------------------------------
// Handshake
// -----------------------------------------------------------------------------

export interface ClientInfo {
  name: string;
  version: string;
  platform: string;
}

export interface PcpHelloPayload {
  token: string;
  client: ClientInfo;
  encoding: 'json';
  capabilities: string[];
}

export type PcpHello = PcpEnvelope<PcpHelloPayload> & {
  kind: 'hello';
  type: 'connection.hello';
};

export interface DaemonInfo {
  version: string;
  startedAt: number;
  pid: number;
}

export interface PiInfo {
  path: string;
  version: string;
  supported: boolean;
}

export interface ProtocolLimits {
  maxFrameBytes: number;
  journalMaxEvents: number;
}

export interface PcpWelcomePayload {
  clientId: string;
  daemon: DaemonInfo;
  pi: PiInfo;
  capabilities: string[];
  limits: ProtocolLimits;
}

export type PcpWelcome = PcpEnvelope<PcpWelcomePayload> & {
  kind: 'welcome';
  type: 'connection.welcome';
};

// -----------------------------------------------------------------------------
// Commands
// -----------------------------------------------------------------------------

export type PcpCommandType =
  | 'pi.packages.list'
  | 'pi.packages.update'
  | 'pi.packages.remove'
  | 'pi.packages.pin'
  | 'pi.agents.get'
  | 'pi.agents.update'
  | 'daemon.getStatus'
  | 'daemon.getConfig'
  | 'daemon.setConfig'
  | 'session.list'
  | 'session.create'
  | 'session.open'
  | 'session.attach'
  | 'session.detach'
  | 'session.closeWorker'
  | 'session.delete'
  | 'session.rename'
  | 'session.fork'
  | 'session.clone'
  | 'session.getTree'
  | 'session.getEntries'
  | 'session.getHistory'
  | 'session.getStats'
  | 'session.getForkPoints'
  | 'session.subagents'
  | 'agent.prompt'
  | 'agent.steer'
  | 'agent.followUp'
  | 'agent.abort'
  | 'agent.clearQueue'
  | 'agent.interrupt'
  | 'agent.compact'
  | 'agent.setContextWindowOverride'
  | 'agent.setCompactionReservePercent'
  | 'agent.setAutoCompaction'
  | 'agent.setAutoRetry'
  | 'agent.abortRetry'
  | 'agent.setModel'
  | 'agent.authLogin'
  | 'agent.authLogout'
  | 'agent.getModels'
  | 'agent.setThinkingLevel'
  | 'agent.getThinkingLevels'
  | 'agent.setSteeringMode'
  | 'agent.setFollowUpMode'
  | 'agent.getCommands'
  | 'ui.claim'
  | 'ui.respond'
  | 'workspace.refresh'
  | 'workspace.getDiff'
  | 'workspace.listFiles'
  | 'workspace.readFile'
  | 'workspace.saveFile'
  | 'workspace.gitAction'
  | 'workspace.listBranches'
  | 'workspace.switchBranch'
  | 'remote.getStatus'
  | 'remote.start'
  | 'remote.stop'
  | 'remote.generatePairing'
  | 'remote.setDeviceMode'
  | 'remote.installCloudflared'
  | 'remote.installTailscale'
  | 'remote.setTailscaleHostname'
  | 'remote.revokeDevice'
  | 'remote.revokeAll'
  | 'remote.setOptions'
  | 'system.metrics.subscribe'
  | 'system.metrics.unsubscribe';

export interface PcpCommand<T = Record<string, unknown>> extends PcpEnvelope<T> {
  kind: 'command';
  commandId: string;
  type: PcpCommandType;
}

export interface PiPackageInfo {
  source: string;
  name: string;
  version: string | null;
  pinnedVersion: string | null;
}

export interface WorkspaceFileInfo {
  path: string;
  sizeBytes: number;
}

export interface WorkspaceListFilesResult {
  rootPath: string;
  files: WorkspaceFileInfo[];
  truncated: boolean;
}

export interface WorkspaceReadFileResult {
  rootPath: string;
  path: string;
  content: string;
  revision: string;
  sizeBytes: number;
}

export interface WorkspaceSaveFileRequest {
  path: string;
  content: string;
  revision: string;
}

export type WorkspaceGitAction = 'stage' | 'unstage' | 'commit' | 'discard';

export interface WorkspaceGitActionRequest {
  action: WorkspaceGitAction;
  paths: string[];
  expectedStagedPaths?: string[];
  message?: string;
}

export interface WorkspaceBranchInfo {
  name: string;
  isCurrent: boolean;
  upstream: string | null;
  ahead: number | null;
  behind: number | null;
  lastCommitUnix: number | null;
}

export interface WorkspaceListBranchesResult {
  branches: WorkspaceBranchInfo[];
  currentBranch: string | null;
  detached: boolean;
  headShortSha: string | null;
}

export interface WorkspaceSwitchBranchPayload {
  branch: string;
  onDirty?: 'block' | 'stash';
}

export interface WorkspaceSwitchBranchResult {
  currentBranch: string;
  stashed: boolean;
  stashMessage: string | null;
}

export interface WorkspaceDirtyDetails {
  changedFiles: number;
  untrackedFiles: number;
}

export interface BranchSwitchFailedDetails {
  stderr?: string;
  stashRetained?: boolean;
  stashMessage?: string | null;
}

// -----------------------------------------------------------------------------
// System Metrics
// -----------------------------------------------------------------------------

export interface SystemMetricsSubscribeResult {
  intervalMs: number;
}

export interface SystemCpuMetrics {
  percent: number;
}

export interface SystemMemoryMetrics {
  usedBytes: number;
  totalBytes: number;
  percent: number;
}

export interface SystemDiskMetrics {
  usedBytes: number;
  totalBytes: number;
  percent: number;
}

export type SystemGpuSource = 'nvidia-smi' | 'typeperf' | 'sysfs' | 'ioreg' | null;

export interface SystemGpuMetrics {
  percent: number | null;
  memoryUsedBytes: number | null;
  memoryTotalBytes: number | null;
  source: SystemGpuSource;
}

export interface SystemMetricsPayload {
  sampledAt: number;
  cpu: SystemCpuMetrics | null;
  memory: SystemMemoryMetrics | null;
  disk: SystemDiskMetrics | null;
  gpu: SystemGpuMetrics;
}

// -----------------------------------------------------------------------------
// Ack & Result
// -----------------------------------------------------------------------------

export type PcpAckState = 'accepted' | 'executing' | 'resume' | 'rejected' | 'deduplicated';

export interface PcpAckPayload {
  state: PcpAckState;
  reason?: string;
}

export interface PcpAck extends PcpEnvelope<PcpAckPayload> {
  kind: 'ack';
  commandId: string;
  type: 'command.ack';
}

export type PcpResultState = 'completed' | 'failed' | 'deduplicated' | 'rejected';

export interface PcpResultPayload<T = Record<string, unknown>> {
  state: PcpResultState;
  data?: T;
  error?: string;
}

export interface PcpResult<T = Record<string, unknown>> extends PcpEnvelope<PcpResultPayload<T>> {
  kind: 'result';
  commandId: string;
  type: 'command.result';
}

// -----------------------------------------------------------------------------
// Normalized Events
// -----------------------------------------------------------------------------

export type PcpEventType =
  | 'session.status'
  | 'run.started'
  | 'run.ended'
  | 'run.settled'
  | 'turn.started'
  | 'turn.ended'
  | 'message.started'
  | 'message.completed'
  | 'text.started'
  | 'text.delta'
  | 'text.completed'
  | 'thinking.started'
  | 'thinking.delta'
  | 'thinking.completed'
  | 'toolcall.started'
  | 'toolcall.argsDelta'
  | 'toolcall.completed'
  | 'usage.updated'
  | 'tool.started'
  | 'tool.progress'
  | 'tool.completed'
  | 'queue.changed'
  | 'compaction.started'
  | 'compaction.ended'
  | 'retry.started'
  | 'retry.ended'
  | 'summarization.retry'
  | 'bash.output'
  | 'extension.error'
  | 'ui.request'
  | 'ui.claimed'
  | 'ui.resolved'
  | 'ui.notify'
  | 'ui.status'
  | 'ui.widget'
  | 'ui.editorText'
  | 'ui.title'
  | 'workspace.changed'
  | 'worker.diagnostic'
  | 'worker.crashed'
  | 'journal.gap'
  | 'session.indexChanged'
  | 'daemon.configChanged'
  | 'remote.statusChanged'
  | 'system.metrics';

export interface PcpEvent<T = Record<string, unknown>> extends PcpEnvelope<T> {
  kind: 'event';
  sessionId: string;
  seq: number;
  type: PcpEventType;
}

export type PcpSystemMetricsEvent = PcpEvent<SystemMetricsPayload> & {
  type: 'system.metrics';
};

// -----------------------------------------------------------------------------
// Snapshots
// -----------------------------------------------------------------------------

export interface SessionMeta {
  id: string;
  name?: string;
  cwd: string;
  gitRoot?: string | null;
  sessionFile?: string | null;
  createdAt?: number;
  lastActivityAt?: number;
}

export interface RuntimeMeta {
  status: string;
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
}

export interface TranscriptMeta {
  entries: Array<Record<string, unknown>>;
  leafId?: string | null;
  totalEntries?: number;
  hasMore?: boolean;
}

export type RemoteDeviceMode = 'view' | 'control';

export interface RemoteDeviceRecord {
  deviceId: string;
  name: string;
  userAgent?: string;
  mode: RemoteDeviceMode;
  createdAt: number;
  lastUsedAt: number;
  expiresAt: number;
  remoteIp?: string;
}

export interface RemoteStatusPayload {
  enabled: boolean;
  state: 'stopped' | 'starting' | 'running' | 'error';
  url?: string;
  tunnelProvider: string;
  cloudflaredInstalled: boolean;
  cloudflaredPath?: string;
  tailscale?: {
    installed: boolean;
    running: boolean;
    hostname?: string;
    domain?: string;
    magicDnsSuffix?: string;
  };
  error?: string;
  localPort?: number;
  devices: RemoteDeviceRecord[];
  pairingPending?: {
    expiresAt: number;
    url?: string;
  };
  options: {
    defaultMode: RemoteDeviceMode;
  };
}

export interface PcpSnapshotPayload {
  session: SessionMeta;
  runtime: RuntimeMeta;
  transcript: TranscriptMeta;
  liveMessage?: Record<string, unknown> | null;
  activeTools: Array<Record<string, unknown>>;
  pendingUiRequests: Array<Record<string, unknown>>;
  usage: Record<string, unknown>;
  workspace: Record<string, unknown>;
}

export interface PcpSnapshot extends PcpEnvelope<PcpSnapshotPayload> {
  kind: 'snapshot';
  sessionId: string;
  seq: number;
  type: 'session.snapshot';
}

// -----------------------------------------------------------------------------
// Errors
// -----------------------------------------------------------------------------

export type PcpErrorCode =
  | 'AUTH_FAILED'
  | 'PROTOCOL_VERSION_UNSUPPORTED'
  | 'INVALID_MESSAGE'
  | 'SESSION_NOT_FOUND'
  | 'SESSION_BUSY'
  | 'WORKER_UNAVAILABLE'
  | 'WORKER_CRASHED'
  | 'PI_NOT_FOUND'
  | 'PI_VERSION_UNSUPPORTED'
  | 'COMMAND_REJECTED'
  | 'COMMAND_TIMEOUT'
  | 'UI_REQUEST_NOT_CLAIMED'
  | 'UI_REQUEST_EXPIRED'
  | 'JOURNAL_GAP'
  | 'CONFIG_INVALID'
  | 'RATE_LIMITED'
  | 'INTERNAL'
  | 'REMOTE_FORBIDDEN'
  | 'BRANCH_INVALID_NAME'
  | 'BRANCH_NOT_FOUND'
  | 'WORKSPACE_DIRTY'
  | 'BRANCH_SWITCH_FAILED'
  | 'AGENTS_VALIDATION_FAILED'
  | 'AGENTS_CONFIG_UNREADABLE'
  | 'AGENTS_CONFIG_LOCKED'
  | 'AGENTS_PACKAGE_NOT_INSTALLED';

export interface PcpErrorPayload {
  code: PcpErrorCode;
  message: string;
  retryable?: boolean;
  details?: Record<string, unknown> | Array<unknown>;
  hint?: string;
}

export interface PcpError extends PcpEnvelope<PcpErrorPayload> {
  kind: 'error';
  type: 'error';
}

// -----------------------------------------------------------------------------
// Ping / Pong
// -----------------------------------------------------------------------------

export interface PcpPing extends PcpEnvelope<Record<string, unknown>> {
  kind: 'ping';
  type: 'heartbeat.ping';
}

export interface PcpPong extends PcpEnvelope<Record<string, unknown>> {
  kind: 'pong';
  type: 'heartbeat.pong';
}

// -----------------------------------------------------------------------------
// Agent Settings (pi.agents.*)
// -----------------------------------------------------------------------------

export type PiSubagentPackageId = 'pi-subagents' | '@tintinweb/pi-subagents';

export interface PiSubagentPackageInfo {
  id: PiSubagentPackageId;
  version: string | null;
  installed: boolean;
  configFile: string;
}

export interface PiAgentModelInfo {
  effective: string | null;
  origin: 'override' | 'frontmatter' | 'default' | 'none';
  available: boolean | null;
}

export interface PiAgentThinkingInfo {
  effective: string | null;
  origin: 'override' | 'frontmatter' | 'default' | 'none';
}

export interface PiAgentContextInfo {
  supported: boolean;
  limit: number | null;
  options: number[];
  modelContextWindow: number | null;
}

export interface PiAgentInfo {
  name: string;
  aliases?: string[];
  package: string | null;
  source: 'builtin' | 'user' | 'project' | 'package';
  description: string | null;
  editable: boolean;
  readOnlyReason: string | null;
  model: PiAgentModelInfo;
  thinking: PiAgentThinkingInfo;
  context: PiAgentContextInfo;
}

export interface PiSubagentDefaults {
  package: string | null;
  model: string | null;
  thinking: string | null;
  modelAvailable: boolean | null;
  fallbackAgent: string | null;
}

export interface PiSessionDefaults {
  provider: string | null;
  model: string | null;
  thinking: string | null;
  modelAvailable: boolean | null;
}

export interface PiAvailableModel {
  id: string;
  name: string;
  contextWindow: number;
  reasoning: boolean;
  tiers: number[];
}

export interface PiAgentsGetResult {
  packages: PiSubagentPackageInfo[];
  agents: PiAgentInfo[];
  subagentDefaults: PiSubagentDefaults;
  sessionDefaults: PiSessionDefaults;
  thinkingLevels: string[];
  availableModels: PiAvailableModel[];
  warnings: string[];
}

export type PiAgentChange =
  | {
      kind: 'agent';
      name: string;
      model?: string | null;
      thinking?: string | null;
      contextLimit?: number | null;
    }
  | {
      kind: 'subagentDefaults';
      model?: string | null;
      thinking?: string | null;
      fallbackAgent?: string | null;
    }
  | {
      kind: 'sessionDefaults';
      model?: string | null;
      thinking?: string | null;
    };

export interface PiAgentsUpdatePayload {
  changes: PiAgentChange[];
}

// -----------------------------------------------------------------------------
// Message Unions
// -----------------------------------------------------------------------------

export type ClientMessage =
  | PcpHello
  | PcpCommand<any>
  | PcpPong;

export type ServerMessage =
  | PcpWelcome
  | PcpAck
  | PcpResult<any>
  | PcpEvent<any>
  | PcpSnapshot
  | PcpError
  | PcpPing;

export type PcpMessage = ClientMessage | ServerMessage;
