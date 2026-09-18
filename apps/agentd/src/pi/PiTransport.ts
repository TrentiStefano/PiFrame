import type { PiCommand, PiResponse, PiEvent, TransportHealth, PiCapabilities, ExitInfo } from './piCommands.js';

export interface PiTransport {
  start(opts: { cwd: string; args?: string[]; env?: Record<string, string> }): Promise<void>;
  send(cmd: PiCommand): Promise<PiResponse>;
  events(): AsyncIterable<PiEvent>;
  health(): TransportHealth;
  capabilities(): PiCapabilities;
  stop(opts: { graceMs: number }): Promise<ExitInfo>;
}
