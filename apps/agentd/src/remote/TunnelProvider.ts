import * as child_process from 'node:child_process';
import { EventEmitter } from 'node:events';

export interface TunnelStartResult {
  url: string;
  provider: string;
}

export type TunnelState = 'stopped' | 'starting' | 'running' | 'error';

export interface TunnelProvider {
  readonly name: string;
  start(localPort: number): Promise<TunnelStartResult>;
  stop(): Promise<void>;
  getUrl(): string | undefined;
  getState(): TunnelState;
  getError(): string | undefined;
  /** Emitted whenever state/url/error change (including unexpected process exit). */
  on(event: 'change', listener: () => void): this;
  removeAllListeners(event?: string): this;
}

/** Shared state handling for tunnel providers. */
export abstract class BaseTunnelProvider extends EventEmitter implements TunnelProvider {
  public abstract readonly name: string;
  protected state: TunnelState = 'stopped';
  protected currentUrl?: string;
  protected errorMessage?: string;
  private startPromise?: Promise<TunnelStartResult>;

  public abstract stop(): Promise<void>;
  protected abstract doStart(localPort: number): Promise<TunnelStartResult>;

  public getState(): TunnelState {
    return this.state;
  }

  public getUrl(): string | undefined {
    return this.currentUrl;
  }

  public getError(): string | undefined {
    return this.errorMessage;
  }

  protected setState(state: TunnelState, patch: { url?: string | null; error?: string | null } = {}): void {
    this.state = state;
    if (patch.url !== undefined) this.currentUrl = patch.url ?? undefined;
    if (patch.error !== undefined) this.errorMessage = patch.error ?? undefined;
    this.emit('change');
  }

  /** Concurrent start() calls share a single in-flight start (no duplicate processes). */
  public start(localPort: number): Promise<TunnelStartResult> {
    if (this.state === 'running' && this.currentUrl) {
      return Promise.resolve({ url: this.currentUrl, provider: this.name });
    }
    if (this.startPromise) return this.startPromise;
    this.startPromise = this.doStart(localPort).finally(() => {
      this.startPromise = undefined;
    });
    return this.startPromise;
  }
}

/**
 * Terminates a child process AND its descendants.
 * - Windows: `taskkill /T /F` (a plain kill only terminates the direct child).
 * - POSIX: signals the process group when the child was spawned `detached`.
 */
export function killProcessTree(proc: child_process.ChildProcess, graceMs = 3000): Promise<void> {
  return new Promise((resolve) => {
    if (!proc.pid || proc.exitCode !== null || proc.signalCode !== null) return resolve();

    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      clearTimeout(forceTimer);
      clearTimeout(giveUpTimer);
      resolve();
    };
    proc.once('exit', finish);

    const signal = (sig: NodeJS.Signals) => {
      try {
        if (process.platform === 'win32') {
          child_process.execFile('taskkill', ['/pid', String(proc.pid), '/T', '/F'], { windowsHide: true }, () => {});
        } else {
          try {
            process.kill(-proc.pid!, sig);
          } catch {
            proc.kill(sig);
          }
        }
      } catch {
        // already gone
      }
    };

    signal('SIGTERM');
    const forceTimer = setTimeout(() => signal('SIGKILL'), graceMs);
    const giveUpTimer = setTimeout(finish, graceMs + 1500);
    forceTimer.unref?.();
    giveUpTimer.unref?.();
  });
}

/**
 * Splits a command line into argv WITHOUT invoking a shell. Supports single and double quotes;
 * backslashes are literal (Windows paths). No expansion, redirection, pipes or substitution.
 */
export function parseCommandLine(input: string): string[] {
  const args: string[] = [];
  let current = '';
  let inToken = false;
  let quote: '"' | "'" | null = null;
  for (const ch of input) {
    if (quote) {
      if (ch === quote) quote = null;
      else current += ch;
    } else if (ch === '"' || ch === "'") {
      quote = ch;
      inToken = true;
    } else if (/\s/.test(ch)) {
      if (inToken) {
        args.push(current);
        current = '';
        inToken = false;
      }
    } else {
      current += ch;
      inToken = true;
    }
  }
  if (quote) throw new Error('Unterminated quote in tunnel command.');
  if (inToken) args.push(current);
  return args;
}
