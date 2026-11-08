import type { PiTransport } from '../pi/PiTransport.js';
import type { PiCommand, PiResponse, PiEvent, TransportHealth, PiCapabilities, ExitInfo } from '../pi/piCommands.js';

export const SIDE_ALLOWED_RPC_COMMANDS = new Set(['prompt', 'abort', 'get_state']);

export class SideTransport implements PiTransport {
  constructor(private readonly inner: PiTransport) {}

  public async start(opts: { cwd: string; args?: string[]; env?: Record<string, string> }): Promise<void> {
    return this.inner.start(opts);
  }

  public async send(cmd: PiCommand): Promise<PiResponse> {
    if (!SIDE_ALLOWED_RPC_COMMANDS.has(cmd.command)) {
      const err = new Error(`RPC command "${cmd.command}" is blocked for side conversation worker`);
      (err as any).code = 'SIDE_RPC_BLOCKED';
      throw err;
    }
    return this.inner.send(cmd);
  }

  public events(): AsyncIterable<PiEvent> {
    return this.inner.events();
  }

  public health(): TransportHealth {
    return this.inner.health();
  }

  public capabilities(): PiCapabilities {
    return this.inner.capabilities();
  }

  public async stop(opts: { graceMs: number }): Promise<ExitInfo> {
    return this.inner.stop(opts);
  }
}
