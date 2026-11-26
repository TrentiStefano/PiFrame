export interface PiCommand {
  id?: string;
  type?: string;
  command: string;
  arguments?: Record<string, any>;
  /** Local transport timeout override; never sent to Pi. */
  timeoutMs?: number;
}

export interface PiResponse {
  type: 'response';
  id?: string;
  command?: string;
  success: boolean;
  data?: any;
  error?: string;
}

/**
 * One line Pi writes on stdout in RPC mode (and the daemon's own `worker.diagnostic`). Pi's output is untrusted
 * JSON: the known events below give each field a type, so a misspelled field is a compile error (#125); anything
 * else is an {@link UnknownPiEvent}. Readers narrow with {@link isKnownPiEvent} and a switch on `type`.
 */
export type PiEvent = KnownPiEvent | UnknownPiEvent;

/** An event type the daemon does not read; it is reported as a diagnostic, never dropped. */
export interface UnknownPiEvent {
  type: string;
}

/** Token usage as Pi reports it; other fields (cache, cost) pass through to clients unread. */
export interface PiUsage {
  input?: number;
  output?: number;
  inputTokens?: number;
  outputTokens?: number;
  totalTokens?: number;
  [field: string]: unknown;
}

/** A conversation message; it passes through to clients whole, so fields the daemon does not read stay unknown. */
export interface PiMessage {
  id?: string;
  role?: string;
  timestamp?: number;
  usage?: PiUsage;
  [field: string]: unknown;
}

interface PiUsageCarrier {
  usage?: PiUsage;
  message?: PiMessage;
}

export interface PiAgentEvent extends PiUsageCarrier {
  type: 'agent_start' | 'agent_end' | 'agent_settled' | 'turn_start' | 'turn_end';
  willRetry?: boolean;
}

export interface PiMessageEvent extends PiUsageCarrier {
  type: 'message_start' | 'message_end';
  id?: string;
  role?: string;
}

export interface PiAssistantMessageDelta {
  type: string;
  contentIndex?: number;
  delta?: string;
  toolCallId?: string;
}

export interface PiMessageUpdateEvent extends PiUsageCarrier {
  type: 'message_update';
  assistantMessageEvent?: PiAssistantMessageDelta;
}

export interface PiToolEvent {
  type: 'tool_execution_start' | 'tool_execution_update' | 'tool_execution_end';
  toolCallId?: string;
  toolName?: string;
  args?: unknown;
  partialResult?: unknown;
  result?: unknown;
  isError?: boolean;
  durationMs?: number;
}

export interface PiQueueEvent {
  type: 'queue_update';
  steering?: string[];
  followUp?: string[];
}

export interface PiCompactionEvent {
  type: 'compaction_start' | 'compaction_end';
  reason?: string;
  result?: unknown;
  aborted?: boolean;
  willRetry?: boolean;
  errorMessage?: string;
}

export interface PiRetryEvent {
  type: 'auto_retry_start' | 'auto_retry_end';
  attempt?: number;
  maxAttempts?: number;
  delayMs?: number;
  errorMessage?: string;
  success?: boolean;
  finalError?: string;
}

export interface PiBashOutputEvent {
  type: 'bash_execution_update';
  id?: string;
  delta?: string;
}

/** An extension's request to the UI: a notification, status, widget, editor text, title, or a dialog to answer. */
export interface PiExtensionUiRequestEvent {
  type: 'extension_ui_request';
  method?: string;
  id?: string;
  requestId?: string;
  title?: string;
  message?: string;
  notifyType?: string;
  level?: string;
  statusKey?: string;
  statusText?: string;
  widgetKey?: string;
  widgetLines?: unknown;
  lines?: unknown;
  widgetPlacement?: string;
  placement?: string;
  text?: string;
  options?: unknown;
  placeholder?: string;
  prefill?: string;
  timeout?: number;
  timeoutMs?: number;
}

export interface PiExtensionErrorEvent {
  type: 'extension_error';
  extensionPath?: string;
  event?: string;
  error?: string;
}

/** Written by the daemon itself (transport and supervisor), not by Pi. */
export interface PiWorkerDiagnosticEvent {
  type: 'worker.diagnostic';
  level?: string;
  message?: string;
  source?: string;
}

export type KnownPiEvent =
  | PiAgentEvent
  | PiMessageEvent
  | PiMessageUpdateEvent
  | PiToolEvent
  | PiQueueEvent
  | PiCompactionEvent
  | PiRetryEvent
  | PiBashOutputEvent
  | PiExtensionUiRequestEvent
  | PiExtensionErrorEvent
  | PiWorkerDiagnosticEvent;

const KNOWN_PI_EVENT_TYPES: ReadonlySet<string> = new Set<KnownPiEvent['type']>([
  'agent_start',
  'agent_end',
  'agent_settled',
  'turn_start',
  'turn_end',
  'message_start',
  'message_end',
  'message_update',
  'tool_execution_start',
  'tool_execution_update',
  'tool_execution_end',
  'queue_update',
  'compaction_start',
  'compaction_end',
  'auto_retry_start',
  'auto_retry_end',
  'bash_execution_update',
  'extension_ui_request',
  'extension_error',
  'worker.diagnostic'
]);

/** Whether an event is one the daemon reads; then a switch on `type` gives each field its type. */
export function isKnownPiEvent(event: PiEvent): event is KnownPiEvent {
  return KNOWN_PI_EVENT_TYPES.has(event.type);
}

export interface TransportHealth {
  alive: boolean;
  pid?: number;
  uptimeSeconds?: number;
  lastSeenMs?: number;
}

export interface PiCapabilities {
  version: string;
  supported: boolean;
  modes: string[];
  features: string[];
  thinkingLevels?: string[];
}

export interface ExitInfo {
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  lastStderr: string[];
}

/** A model as Pi reports it. The fields the daemon reads are typed; the rest pass through unchanged. */
export interface PiModelInfo {
  provider?: string;
  id?: string;
  name?: string;
  contextWindow?: number;
  piframeOriginalContextWindow?: number;
  /** Pi's reasoning flag and price table; the daemon narrows each before reading it. */
  reasoning?: unknown;
  cost?: unknown;
  [key: string]: unknown;
}

/** The model's fields when Pi reported it as an object; a bare model id has none. */
export function modelInfoOf(model: PiModelInfo | string | null | undefined): PiModelInfo | undefined {
  return typeof model === 'string' ? undefined : (model ?? undefined);
}
