import * as fs from 'node:fs';
import * as path from 'node:path';
import { getPiFrameBaseDir } from '../config/config.js';
import { StdioPiTransport } from '../pi/StdioPiTransport.js';
import type { Session } from './Session.js';
import type { PiCapabilities } from '../pi/piCommands.js';
import { SessionIndex } from './SessionIndex.js';
import { ensureContextLimitExtension, applyContextPolicy, physicalModel } from '../pi/contextLimitExtension.js';
import { DEFAULT_COMPACTION_RESERVE_PERCENT, writeContextPolicy } from '../pi/contextPolicy.js';

export interface WorkerSupervisorOptions {
  piExecutablePath: string;
  capabilities: PiCapabilities;
  defaultIdleTimeoutMs: number;
  checkTerminalOwner: (cwd: string, sessionFile?: string | null, sessionId?: string) => Promise<boolean | null>;
}

export class WorkerSupervisor {
  private piExecutablePath: string;
  private capabilities: PiCapabilities;
  private idleTimeoutMs: number;
  private checkTerminalOwner: (cwd: string, sessionFile?: string | null, sessionId?: string) => Promise<boolean | null>;
  private idleTimers = new Map<string, NodeJS.Timeout>();
  private activeWorkers = new Map<string, StdioPiTransport>();
  private startingWorkers = new Map<string, Promise<StdioPiTransport>>();
  private sessions = new Map<string, Session>();
  private workerSessions = new Map<StdioPiTransport, Session>();
  private stoppingWorkers = new Set<StdioPiTransport>();
  private stoppingTasks = new Map<string, Promise<void>>();
  private shuttingDown = false;

  constructor(opts: WorkerSupervisorOptions) {
    this.piExecutablePath = opts.piExecutablePath;
    this.capabilities = opts.capabilities;
    this.idleTimeoutMs = opts.defaultIdleTimeoutMs;
    this.checkTerminalOwner = opts.checkTerminalOwner;
  }

  public updateIdleTimeout(newTimeoutMs: number): void {
    this.idleTimeoutMs = newTimeoutMs;
    // Reschedule all active idle timers with the new timeout immediately
    for (const [sessionId, timer] of this.idleTimers.entries()) {
      clearTimeout(timer);
      this.idleTimers.delete(sessionId);
      this.scheduleIdleTimeout(sessionId);
    }
  }

  public async ensureWorker(session: Session): Promise<StdioPiTransport> {
    if (session.readOnly) throw new Error('External session is read-only. Duplicate it before sending commands.');
    if (this.shuttingDown) throw new Error('Daemon is shutting down');
    await this.stoppingTasks.get(session.id);
    if (this.shuttingDown) throw new Error('Daemon is shutting down');
    const starting = this.startingWorkers.get(session.id);
    if (starting) return starting;
    const task = this.startWorker(session);
    this.startingWorkers.set(session.id, task);
    try { return await task; } finally { this.startingWorkers.delete(session.id); }
  }

  private async startWorker(session: Session): Promise<StdioPiTransport> {
    const existing = this.activeWorkers.get(session.id);
    if (existing && existing.health().alive) {
      this.touch(session.id);
      return existing;
    }

    // Clean up dead reference if any
    if (existing) {
      this.activeWorkers.delete(session.id);
    }

    if (session.sessionFile) {
      const terminalOwner = await this.checkTerminalOwner(session.cwd, session.sessionFile, session.id);
      if (terminalOwner === true || (terminalOwner === null && !session.allowAmbiguousTerminal)) {
        session.readOnly = true;
        session.readOnlyReason = terminalOwner === true ? 'terminal' : 'unknown';
        throw new Error(terminalOwner === true
          ? 'An interactive Pi terminal is using this session. Duplicate it to continue safely.'
          : 'PiFrame could not verify which session is open in this project. Confirm before continuing.');
      }
    }

    const worker = new StdioPiTransport({
      executablePath: this.piExecutablePath,
      capabilities: this.capabilities
    });

    const args = ['--mode', 'rpc', '--extension', ensureContextLimitExtension()];
    if (session.forkSourceFile) {
      args.push('--fork', session.forkSourceFile, '--session-id', session.id);
    } else if (session.sessionFile) {
      args.push('--session', session.sessionFile);
    } else {
      args.push('--session-id', session.id);
    }
    if (session.name && !session.sessionFile) args.push('--name', session.name);

    await worker.start({
      cwd: session.cwd,
      args
    });

    session.worker = worker;
    this.activeWorkers.set(session.id, worker);
    this.sessions.set(session.id, session);
    this.workerSessions.set(worker, session);
    this.touch(session.id);

    void this.pumpEvents(session, worker);
    try {
      await this.refreshSession(session, worker);
      if (session.contextWindowOverride !== null || session.compactionReservePercent !== DEFAULT_COMPACTION_RESERVE_PERCENT) {
        const maximum = session.model?.contextWindow;
        if (typeof maximum === 'number' && session.contextWindowOverride !== null && session.contextWindowOverride > maximum) {
          session.contextWindowOverride = maximum;
          writeContextPolicy(session.id, session);
        }
        session.model = await applyContextPolicy(worker, session);
      }
      session.forkSourceFile = undefined;
      return worker;
    } catch (error) {
      await this.stopWorker(session.id);
      throw error;
    }
  }

  public async refreshSession(session: Session, worker: StdioPiTransport): Promise<void> {
    const state = (await worker.send({ command: 'get_state' })).data;
    if (state?.sessionFile) session.sessionFile = state.sessionFile;
    session.model = physicalModel(state?.model) || null;
    if (typeof state?.autoCompactionEnabled === 'boolean') session.autoCompaction = state.autoCompactionEnabled;
    session.thinkingLevel = state?.thinkingLevel || null;
    session.isStreaming = !!state?.isStreaming;
    session.isCompacting = !!state?.isCompacting;
    const response = await worker.send({ command: 'get_entries' });
    session.entries = SessionIndex.projectTranscript(response.data?.entries || []);
    session.leafId = response.data?.leafId || null;
  }

  public rekeySession(previous: Session, next: Session): void {
    const worker = this.activeWorkers.get(previous.id);
    if (!worker) throw new Error('Fork worker is not running');
    const timer = this.idleTimers.get(previous.id);
    if (timer) clearTimeout(timer);
    this.idleTimers.delete(previous.id);
    this.activeWorkers.delete(previous.id);
    this.sessions.delete(previous.id);
    this.activeWorkers.set(next.id, worker);
    this.sessions.set(next.id, next);
    this.workerSessions.set(worker, next);
    previous.worker = undefined;
    next.worker = worker;
    this.touch(next.id);
  }

  private async pumpEvents(session: Session, worker: StdioPiTransport): Promise<void> {
    try {
      for await (const event of worker.events()) {
        session = this.workerSessions.get(worker) || session;
        this.touch(session.id);
        session.dispatchPiEvent(event);
      }
    } catch (err: any) {
      session.emitCustomEvent('worker.diagnostic', {
        level: 'warn',
        message: `Event pump error: ${err.message}`,
        source: 'supervisor'
      });
    } finally {
      // Worker stopped or crashed
      session = this.workerSessions.get(worker) || session;
      this.workerSessions.delete(worker);
      if (this.activeWorkers.get(session.id) !== worker) return;
      this.activeWorkers.delete(session.id);
      const timer = this.idleTimers.get(session.id);
      if (timer) {
        clearTimeout(timer);
        this.idleTimers.delete(session.id);
      }

      const health = worker.health();
      if (!health.alive && !this.stoppingWorkers.delete(worker)) {
        const exitInfo = await worker.stop({ graceMs: 1000 });

        // Persist crash diagnostics to ~/.piframe/journal/<sessionId>/crash-<ts>.log
        try {
          const journalDir = path.join(getPiFrameBaseDir(), 'journal', session.id);
          fs.mkdirSync(journalDir, { recursive: true });
          const crashLogPath = path.join(journalDir, `crash-${Date.now()}.log`);
          const crashContent = [
            `Timestamp: ${new Date().toISOString()}`,
            `SessionId: ${session.id}`,
            `ExitCode: ${exitInfo.exitCode}`,
            `Signal: ${exitInfo.signal}`,
            `StatusAtCrash: ${session.status}`,
            `IsStreaming: ${session.isStreaming}`,
            '--- Last Stderr ---',
            ...exitInfo.lastStderr
          ].join('\n');
          fs.writeFileSync(crashLogPath, crashContent, 'utf8');
        } catch {
          // Non-fatal if filesystem write fails
        }

        const safeRestart = session.status === 'settled' && !session.isStreaming;

        session.emitCustomEvent('worker.crashed', {
          exitCode: exitInfo.exitCode,
          signal: exitInfo.signal,
          lastStderr: exitInfo.lastStderr,
          recoverable: safeRestart
        });
      }
    }
  }

  public async reconcileAndRespawn(session: Session): Promise<void> {
    // 1. Ensure worker is spawned for this session
    const worker = await this.ensureWorker(session);

    // 2. Query Pi for existing entries using the durable cursor
    try {
      const res = await worker.send({
        command: 'get_entries',
        arguments: session.leafId ? { since: session.leafId } : {}
      });

      if (res && res.data) {
        session.reconcileEntries(res.data.entries || [], res.data.leafId);
      }
    } catch {
      // If get_entries fails, proceed with current entries
    }

    // 3. Reset session status to settled
    session.status = 'settled';
    session.isStreaming = false;

    // 4. Emit session.status update
    session.emitCustomEvent('session.status', {
      status: 'settled',
      reason: 'recovered_from_crash'
    });
  }

  public touch(sessionId: string): void {
    const existingTimer = this.idleTimers.get(sessionId);
    if (existingTimer) {
      clearTimeout(existingTimer);
      this.idleTimers.delete(sessionId);
    }
    this.scheduleIdleTimeout(sessionId);
  }

  private scheduleIdleTimeout(sessionId: string): void {
    if (this.idleTimeoutMs <= 0) return; // 0 = never idle timeout

    const timer = setTimeout(() => {
      void this.checkAndStopIdleWorker(sessionId);
    }, this.idleTimeoutMs);

    this.idleTimers.set(sessionId, timer);
  }

  private async checkAndStopIdleWorker(sessionId: string): Promise<void> {
    const worker = this.activeWorkers.get(sessionId);
    if (!worker) return;

    const session = this.sessions.get(sessionId);
    if (session && session.sessionFile && fs.existsSync(session.sessionFile) &&
        session.status === 'settled' && !session.isStreaming && !session.isCompacting &&
        session.uiBroker.getPending().length === 0) {
      await this.stopWorker(sessionId);
    } else {
      this.touch(sessionId);
    }
  }

  public async stopWorker(sessionId: string, graceMs = 5000): Promise<void> {
    const pending = this.stoppingTasks.get(sessionId);
    if (pending) return pending;
    const stopping = this.stopWorkerNow(sessionId, graceMs);
    this.stoppingTasks.set(sessionId, stopping);
    try { await stopping; } finally { this.stoppingTasks.delete(sessionId); }
  }

  private async stopWorkerNow(sessionId: string, graceMs: number): Promise<void> {
    const timer = this.idleTimers.get(sessionId);
    if (timer) {
      clearTimeout(timer);
      this.idleTimers.delete(sessionId);
    }

    const worker = this.activeWorkers.get(sessionId);
    if (worker) {
      this.stoppingWorkers.add(worker);
      await worker.stop({ graceMs });
      if (this.activeWorkers.get(sessionId) === worker) this.activeWorkers.delete(sessionId);
      this.stoppingWorkers.delete(worker);
    }
  }

  public async stopAll(graceMs = 5000): Promise<void> {
    this.shuttingDown = true;
    await Promise.allSettled(this.startingWorkers.values());
    const sessionIds = Array.from(this.activeWorkers.keys());
    await Promise.all(sessionIds.map((sid) => this.stopWorker(sid, graceMs)));
  }
}
