import { spawn, type ChildProcess } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { ulid } from 'ulid';
import type { PiTransport } from './PiTransport.js';
import type { PiCommand, PiResponse, PiEvent, TransportHealth, PiCapabilities, ExitInfo } from './piCommands.js';
import { JsonlFramer } from './jsonlFramer.js';

export interface StdioPiTransportOptions {
  executablePath: string;
  capabilities?: PiCapabilities;
}

export class StdioPiTransport implements PiTransport {
  private executablePath: string;
  private child?: ChildProcess;
  private framer = new JsonlFramer();
  private startedAt = 0;
  private lastSeenMs = 0;
  private exitPromise?: Promise<ExitInfo>;
  private exitInfo: ExitInfo = { exitCode: null, signal: null, lastStderr: [] };

  // 200-line circular ring buffer for stderr
  private stderrRingBuffer: string[] = [];
  private readonly maxStderrLines = 200;

  // Command correlation
  private pendingCommands = new Map<
    string,
    {
      resolve: (res: PiResponse) => void;
      reject: (err: Error) => void;
      command: string;
      timer?: NodeJS.Timeout;
    }
  >();
  private fifoPendingCommands: Array<{
    command: string;
    resolve: (res: PiResponse) => void;
    reject: (err: Error) => void;
  }> = [];

  // Async event queue
  private eventQueue: PiEvent[] = [];
  private eventWaiters: Array<(event: PiEvent | null) => void> = [];
  private isStopped = false;

  private caps: PiCapabilities;

  constructor(opts: StdioPiTransportOptions) {
    this.executablePath = opts.executablePath;
    this.caps = opts.capabilities ?? {
      version: '0.85.1',
      supported: true,
      modes: ['rpc'],
      features: ['thinking', 'tools', 'compaction']
    };
  }

  public async start(opts: { cwd: string; args?: string[]; env?: Record<string, string> }): Promise<void> {
    const cwd = opts.cwd;
    const extraArgs = opts.args ?? [];
    const env = { ...process.env, ...opts.env, PI_CRUST: '1' };

    let spawnFile = this.executablePath;
    let spawnArgs = [...extraArgs];

    // Windows optimization: If targeting a .js file or known Node bundle, execute via node directly
    if (spawnFile.endsWith('.js')) {
      spawnArgs = [spawnFile, ...spawnArgs];
      spawnFile = process.execPath;
    } else if (process.platform === 'win32') {
      // Check if it's a wrapper .cmd with adjacent cli.js
      const dir = path.dirname(spawnFile);
      const possibleCli = path.join(dir, 'node_modules', '@earendil-works', 'pi-coding-agent', 'dist', 'bundle', 'cli.js');
      if (fs.existsSync(possibleCli)) {
        spawnArgs = [possibleCli, ...spawnArgs];
        spawnFile = process.execPath;
      }
    }

    this.startedAt = Date.now();
    this.lastSeenMs = this.startedAt;

    this.child = spawn(spawnFile, spawnArgs, {
      cwd,
      env,
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: false,
      windowsHide: true
    });

    this.exitPromise = new Promise<ExitInfo>((resolve) => {
      this.child!.on('exit', (code, signal) => {
        this.exitInfo = {
          exitCode: code,
          signal,
          lastStderr: [...this.stderrRingBuffer]
        };
        this.isStopped = true;
        // Wake up any waiting events iterators
        for (const waiter of this.eventWaiters) {
          waiter(null);
        }
        this.eventWaiters = [];
        resolve(this.exitInfo);
      });
    });

    // Handle stdout via JsonlFramer
    this.child.stdout!.on('data', (chunk: Buffer) => {
      this.lastSeenMs = Date.now();
      const results = this.framer.push(chunk);
      for (const res of results) {
        if (res.ok && res.value) {
          this.handleIncomingObject(res.value);
        } else if (!res.ok) {
          // Emit diagnostic warning rather than crashing
          this.enqueueEvent({
            type: 'worker.diagnostic',
            level: 'warn',
            message: `Unparseable line from Pi: ${res.raw.slice(0, 200)}`,
            source: 'stderr'
          });
        }
      }
    });

    // Handle stderr ring buffer
    let stderrRemainder = '';
    this.child.stderr!.on('data', (chunk: Buffer) => {
      this.lastSeenMs = Date.now();
      const text = stderrRemainder + chunk.toString('utf8');
      const lines = text.split(/\r?\n/);
      stderrRemainder = lines.pop() ?? '';

      for (const line of lines) {
        if (!line.trim()) continue;
        this.stderrRingBuffer.push(line);
        if (this.stderrRingBuffer.length > this.maxStderrLines) {
          this.stderrRingBuffer.shift();
        }
      }
    });
  }

  private handleIncomingObject(obj: any): void {
    if (obj.type === 'response') {
      const resp = obj as PiResponse;
      if (resp.id && this.pendingCommands.has(resp.id)) {
        const entry = this.pendingCommands.get(resp.id)!;
        if (entry.timer) clearTimeout(entry.timer);
        this.pendingCommands.delete(resp.id);
        entry.resolve(resp);
        return;
      }

      // If response lacks ID or was not found, match FIFO by command name
      if (this.fifoPendingCommands.length > 0) {
        const idx = this.fifoPendingCommands.findIndex((e) => !resp.command || e.command === resp.command);
        if (idx !== -1) {
          const entry = this.fifoPendingCommands.splice(idx, 1)[0];
          entry.resolve(resp);
          return;
        }
      }
    }

    // Normal Pi event -> push to async iterator queue
    this.enqueueEvent(obj);
  }

  private enqueueEvent(event: PiEvent): void {
    if (this.eventWaiters.length > 0) {
      const waiter = this.eventWaiters.shift()!;
      waiter(event);
    } else {
      this.eventQueue.push(event);
    }
  }

  public async send(cmd: PiCommand): Promise<PiResponse> {
    if (!this.child || !this.child.stdin || this.child.killed || this.isStopped) {
      throw new Error('Pi worker is not running');
    }

    const commandId = cmd.id || `pi_${ulid()}`;
    cmd.id = commandId;

    const payload = JSON.stringify(cmd) + '\n';

    return new Promise<PiResponse>((resolve, reject) => {
      const timeoutMs = cmd.command === 'abort' ? undefined : 30_000;
      let timer: NodeJS.Timeout | undefined;

      if (timeoutMs) {
        timer = setTimeout(() => {
          this.pendingCommands.delete(commandId);
          reject(new Error(`Command ${cmd.command} (id=${commandId}) timed out after ${timeoutMs}ms`));
        }, timeoutMs);
      }

      this.pendingCommands.set(commandId, {
        resolve,
        reject,
        command: cmd.command,
        timer
      });

      this.fifoPendingCommands.push({
        command: cmd.command,
        resolve,
        reject
      });

      this.child!.stdin!.write(payload, 'utf8', (err) => {
        if (err) {
          if (timer) clearTimeout(timer);
          this.pendingCommands.delete(commandId);
          reject(err);
        }
      });
    });
  }

  public async *events(): AsyncIterable<PiEvent> {
    while (!this.isStopped) {
      if (this.eventQueue.length > 0) {
        yield this.eventQueue.shift()!;
      } else {
        const next = await new Promise<PiEvent | null>((resolve) => {
          this.eventWaiters.push(resolve);
        });
        if (next === null) break;
        yield next;
      }
    }
  }

  public health(): TransportHealth {
    return {
      alive: !this.isStopped && !!this.child && !this.child.killed,
      pid: this.child?.pid,
      uptimeSeconds: this.startedAt ? Math.floor((Date.now() - this.startedAt) / 1000) : 0,
      lastSeenMs: this.lastSeenMs
    };
  }

  public capabilities(): PiCapabilities {
    return this.caps;
  }

  public async stop(opts: { graceMs: number }): Promise<ExitInfo> {
    if (this.isStopped || !this.child || this.child.killed) {
      return this.exitInfo;
    }

    const graceMs = opts.graceMs || 5000;

    try {
      this.child.kill('SIGTERM');
    } catch {}

    const forceKillTimer = setTimeout(() => {
      if (this.child && !this.child.killed) {
        try {
          this.child.kill('SIGKILL');
        } catch {}
      }
    }, graceMs);

    const info = await this.exitPromise!;
    clearTimeout(forceKillTimer);
    return info;
  }
}
