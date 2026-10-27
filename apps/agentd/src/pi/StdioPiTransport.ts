import { spawn, type ChildProcess } from 'node:child_process';
import { ulid } from 'ulid';
import type { PiTransport } from './PiTransport.js';
import type { PiCommand, PiResponse, PiEvent, TransportHealth, PiCapabilities, ExitInfo } from './piCommands.js';
import { JsonlFramer } from './jsonlFramer.js';
import { resolvePiLaunch } from './executable.js';

export interface StdioPiTransportOptions {
  executablePath: string;
  capabilities?: PiCapabilities;
  /** Per-command response timeout. Defaults to 30s; overridable for tests. */
  commandTimeoutMs?: number;
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
    id: string;
    command: string;
    resolve: (res: PiResponse) => void;
    reject: (err: Error) => void;
  }> = [];

  // Async event queue
  private eventQueue: PiEvent[] = [];
  private eventWaiters: Array<(event: PiEvent | null) => void> = [];
  private isStopped = false;

  private caps: PiCapabilities;
  private commandTimeoutMs: number;

  constructor(opts: StdioPiTransportOptions) {
    this.executablePath = opts.executablePath;
    this.commandTimeoutMs = opts.commandTimeoutMs ?? 30_000;
    this.caps = opts.capabilities ?? {
      version: '0.85.1',
      supported: true,
      modes: ['rpc'],
      features: ['thinking', 'tools', 'compaction']
    };
  }

  public async start(opts: { cwd: string; args?: string[]; env?: Record<string, string> }): Promise<void> {
    const launch = resolvePiLaunch(this.executablePath, opts.args ?? []);
    const env = { ...process.env, ...opts.env, PI_FRAME: '1' };
    this.startedAt = Date.now();
    this.lastSeenMs = this.startedAt;

    this.child = spawn(launch.file, launch.args, {
      cwd: opts.cwd,
      env,
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: false,
      windowsHide: true
    });

    let resolveExit!: (info: ExitInfo) => void;
    this.exitPromise = new Promise<ExitInfo>((resolve) => { resolveExit = resolve; });
    let exitFinished = false;
    const finishExit = (code: number | null, signal: NodeJS.Signals | null, cause?: Error) => {
      if (exitFinished) return;
      exitFinished = true;
      this.exitInfo = { exitCode: code, signal, lastStderr: [...this.stderrRingBuffer] };
      this.isStopped = true;
      const failure = cause ?? new Error(`Pi worker exited (code=${code}, signal=${signal ?? 'none'})`);
      for (const entry of this.pendingCommands.values()) {
        if (entry.timer) clearTimeout(entry.timer);
        entry.reject(failure);
      }
      this.pendingCommands.clear();
      this.fifoPendingCommands = [];
      for (const waiter of this.eventWaiters) waiter(null);
      this.eventWaiters = [];
      resolveExit(this.exitInfo);
    };

    const spawned = new Promise<void>((resolve, reject) => {
      this.child!.once('spawn', resolve);
      this.child!.once('error', (err) => {
        finishExit(null, null, err);
        reject(err);
      });
    });
    this.child.once('exit', (code, signal) => finishExit(code, signal));

    this.child.stdout!.on('data', (chunk: Buffer) => {
      this.lastSeenMs = Date.now();
      for (const res of this.framer.push(chunk)) {
        if (res.ok && res.value) {
          this.handleIncomingObject(res.value);
        } else if (!res.ok) {
          this.enqueueEvent({
            type: 'worker.diagnostic',
            level: 'warn',
            message: `Unparseable line from Pi: ${res.raw.slice(0, 200)}`,
            source: 'stderr'
          });
        }
      }
    });

    let stderrRemainder = '';
    this.child.stderr!.on('data', (chunk: Buffer) => {
      this.lastSeenMs = Date.now();
      const lines = (stderrRemainder + chunk.toString('utf8')).split(/\r?\n/);
      stderrRemainder = lines.pop() ?? '';
      for (const line of lines) {
        if (!line.trim()) continue;
        this.stderrRingBuffer.push(line);
        if (this.stderrRingBuffer.length > this.maxStderrLines) this.stderrRingBuffer.shift();
      }
    });

    await spawned;
  }

  private handleIncomingObject(obj: any): void {
    if (obj.type === 'response') {
      const resp = obj as PiResponse;
      if (resp.id) {
        const entry = this.pendingCommands.get(resp.id);
        if (entry) {
          this.completePending(resp.id, entry, resp);
          return;
        }
        // An explicit unknown ID is a late or foreign response, never a FIFO match.
        return;
      }

      const fallback = this.fifoPendingCommands.find((pending) => !resp.command || pending.command === resp.command);
      if (fallback) {
        const entry = this.pendingCommands.get(fallback.id);
        if (entry) {
          this.completePending(fallback.id, entry, resp);
          return;
        }
      }
    }

    this.enqueueEvent(obj);
  }

  private completePending(id: string, entry: { resolve: (res: PiResponse) => void; reject: (err: Error) => void; timer?: NodeJS.Timeout }, response: PiResponse): void {
    if (entry.timer) clearTimeout(entry.timer);
    this.pendingCommands.delete(id);
    this.fifoPendingCommands = this.fifoPendingCommands.filter((pending) => pending.id !== id);
    if (response.success) entry.resolve(response);
    else entry.reject(new Error(response.error || `Pi command ${response.command ?? 'unknown'} failed`));
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

    const command = cmd.command;
    const arguments_ = cmd.arguments ?? {};
    const isUiResponse = command === 'extension_ui_response';
    const commandId = isUiResponse ? String(arguments_.id ?? '') : (cmd.id || `pi_${ulid()}`);
    const payload = JSON.stringify({ type: command, ...arguments_, id: commandId }) + '\n';

    if (isUiResponse) {
      return new Promise<PiResponse>((resolve, reject) => {
        this.child!.stdin!.write(payload, 'utf8', (err) => {
          if (err) reject(err);
          else resolve({ type: 'response', id: commandId, command, success: true });
        });
      });
    }

    return new Promise<PiResponse>((resolve, reject) => {
      const timeoutMs = command === 'abort' ? undefined : this.commandTimeoutMs;
      let timer: NodeJS.Timeout | undefined;
      const removePending = () => {
        if (timer) clearTimeout(timer);
        this.pendingCommands.delete(commandId);
        this.fifoPendingCommands = this.fifoPendingCommands.filter((pending) => pending.id !== commandId);
      };
      if (timeoutMs) {
        timer = setTimeout(() => {
          if (command === 'prompt') {
            // Pi acks a prompt only after preflight (e.g. pre-prompt compaction of a large session, slow extension
            // hooks), which can outlast the timeout. The process is alive and the prompt was written, so report it as
            // accepted instead of a false "not delivered"; a late Pi rejection is surfaced as a diagnostic.
            const entry = this.pendingCommands.get(commandId);
            if (entry) {
              entry.timer = undefined;
              entry.resolve = () => {};
              entry.reject = (err) => this.enqueueEvent({
                type: 'worker.diagnostic',
                level: 'error',
                message: `Pi rejected the prompt after a slow acknowledgement: ${err.message}`,
                source: 'pi'
              });
            }
            resolve({ type: 'response', id: commandId, command, success: true, data: { disposition: 'pending' } });
            return;
          }
          removePending();
          reject(new Error(`Command ${command} (id=${commandId}) timed out after ${timeoutMs}ms`));
        }, timeoutMs);
      }

      this.pendingCommands.set(commandId, { resolve, reject, command, timer });
      this.fifoPendingCommands.push({ id: commandId, command, resolve, reject });
      this.child!.stdin!.write(payload, 'utf8', (err) => {
        if (err) {
          removePending();
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
    if (!this.child || !this.exitPromise) return this.exitInfo;
    if (this.isStopped) return this.exitPromise;

    const graceMs = opts.graceMs || 5000;
    if (!this.child.killed) {
      try { this.child.kill('SIGTERM'); } catch {}
    }

    const forceKillTimer = setTimeout(() => {
      if (this.child && !this.isStopped) {
        try { this.child.kill('SIGKILL'); } catch {}
      }
    }, graceMs);

    const info = await this.exitPromise;
    clearTimeout(forceKillTimer);
    return info;
  }
}
