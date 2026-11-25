export interface PiCommand {
  id?: string;
  type?: string;
  command: string;
  arguments?: Record<string, any>;
  /** Local transport timeout override; never sent to Pi. */
  timeoutMs?: number;
  [key: string]: any;
}

export interface PiResponse {
  type: 'response';
  id?: string;
  command?: string;
  success: boolean;
  data?: any;
  error?: string;
}

export interface PiEvent {
  type: string;
  [key: string]: any;
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
