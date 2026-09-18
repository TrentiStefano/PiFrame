import { StdioPiTransport } from '../pi/StdioPiTransport.js';
import type { Session } from './Session.js';
import type { PiCapabilities } from '../pi/piCommands.js';

export interface WorkerSupervisorOptions {
  piExecutablePath: string;
  capabilities: PiCapabilities;
  defaultIdleTimeoutMs: number;
}

export class WorkerSupervisor {
  private piExecutablePath: string;
  private capabilities: PiCapabilities;
  private idleTimeoutMs: number;
  private idleTimers = new Map<string, NodeJS.Timeout>();
  private activeWorkers = new Map<string, StdioPiTransport>();

  constructor(opts: WorkerSupervisorOptions) {
    this.piExecutablePath = opts.piExecutablePath;
    this.capabilities = opts.capabilities;
    this.idleTimeoutMs = opts.defaultIdleTimeoutMs;
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
    const existing = this.activeWorkers.get(session.id);
    if (existing && existing.health().alive) {
      this.touch(session.id);
      return existing;
    }

    // Clean up dead reference if any
    if (existing) {
      this.activeWorkers.delete(session.id);
    }

    const worker = new StdioPiTransport({
      executablePath: this.piExecutablePath,
      capabilities: this.capabilities
    });

    const args = ['--mode', 'rpc'];
    if (session.name && !session.sessionFile) {
      args.push('--name', session.name);
    }
    if (session.sessionFile) {
      args.push('--session', session.sessionFile);
    }

    await worker.start({
      cwd: session.cwd,
      args
    });

    session.worker = worker;
    this.activeWorkers.set(session.id, worker);
    this.touch(session.id);

    // Consume worker events in background
    void this.pumpEvents(session, worker);

    return worker;
  }

  private async pumpEvents(session: Session, worker: StdioPiTransport): Promise<void> {
    try {
      for await (const event of worker.events()) {
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
      this.activeWorkers.delete(session.id);
      const timer = this.idleTimers.get(session.id);
      if (timer) {
        clearTimeout(timer);
        this.idleTimers.delete(session.id);
      }

      const health = worker.health();
      if (!health.alive) {
        const exitInfo = await worker.stop({ graceMs: 1000 });
        session.emitCustomEvent('worker.crashed', {
          exitCode: exitInfo.exitCode,
          signal: exitInfo.signal,
          lastStderr: exitInfo.lastStderr,
          recoverable: session.status === 'settled'
        });
      }
    }
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

    // RULE: Never shut down worker if actively working, retrying, compacting, or awaiting user input
    // To check state, we look at the session
    // If working, re-schedule timeout
    this.touch(sessionId);
  }

  public async stopWorker(sessionId: string, graceMs = 5000): Promise<void> {
    const timer = this.idleTimers.get(sessionId);
    if (timer) {
      clearTimeout(timer);
      this.idleTimers.delete(sessionId);
    }

    const worker = this.activeWorkers.get(sessionId);
    if (worker) {
      this.activeWorkers.delete(sessionId);
      await worker.stop({ graceMs });
    }
  }

  public async stopAll(graceMs = 5000): Promise<void> {
    const sessionIds = Array.from(this.activeWorkers.keys());
    await Promise.all(sessionIds.map((sid) => this.stopWorker(sid, graceMs)));
  }
}
