export interface PiCommand {
  id?: string;
  type?: string;
  command: string;
  arguments?: Record<string, any>;
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
