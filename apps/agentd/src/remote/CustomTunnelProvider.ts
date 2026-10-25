import * as child_process from 'node:child_process';
import { validateCustomTunnelUrl } from '../config/config.js';
import {
  BaseTunnelProvider,
  killProcessTree,
  parseCommandLine,
  type TunnelStartResult
} from './TunnelProvider.js';

export interface CustomTunnelOptions {
  url?: string;
  command?: string;
}

/**
 * Custom tunnel: the user supplies the public https URL and (optionally) a command that keeps the
 * tunnel alive. The command is executed WITHOUT a shell (argv only) and `$PORT` is substituted with
 * the port of the dedicated remote listener.
 */
export class CustomTunnelProvider extends BaseTunnelProvider {
  public readonly name = 'custom';
  private process?: child_process.ChildProcess;
  private stopping = false;
  private options: CustomTunnelOptions;

  constructor(options: CustomTunnelOptions = {}) {
    super();
    this.options = options;
  }

  protected async doStart(localPort: number): Promise<TunnelStartResult> {
    this.stopping = false;
    this.setState('starting', { error: null, url: null });

    let url: string;
    try {
      url = validateCustomTunnelUrl(this.options.url);
    } catch (err: any) {
      const message = this.options.url
        ? err.message
        : 'Custom tunnel requires a public https URL';
      this.setState('error', { error: message });
      throw new Error(message);
    }

    if (this.options.command) {
      let argv: string[];
      try {
        argv = parseCommandLine(this.options.command).map((a) => a.split('$PORT').join(String(localPort)));
        if (argv.length === 0) throw new Error('Empty tunnel command.');
      } catch (err: any) {
        this.setState('error', { error: err.message });
        throw err;
      }

      const [exe, ...args] = argv;
      const proc = child_process.spawn(exe, args, {
        shell: false,
        stdio: 'ignore', // never leave pipes undrained
        windowsHide: true,
        detached: process.platform !== 'win32'
      });
      this.process = proc;

      try {
        await new Promise<void>((resolve, reject) => {
          proc.once('spawn', () => resolve());
          proc.once('error', reject);
        });
      } catch (err: any) {
        this.process = undefined;
        this.setState('error', { error: `Tunnel command failed to start: ${err.message}` });
        throw new Error(`Tunnel command failed to start: ${err.message}`);
      }

      proc.on('error', (err) => {
        if (this.process !== proc) return;
        this.setState('error', { error: err.message, url: null });
      });
      proc.on('exit', (code, signal) => {
        if (this.process !== proc) return;
        this.process = undefined;
        if (this.stopping) return;
        this.setState('error', { error: `Tunnel command exited unexpectedly (code ${code ?? signal})`, url: null });
      });
    }

    this.setState('running', { url, error: null });
    return { url, provider: this.name };
  }

  public async stop(): Promise<void> {
    this.stopping = true;
    const proc = this.process;
    this.process = undefined;
    if (proc) await killProcessTree(proc);
    this.setState('stopped', { url: null, error: null });
  }
}
