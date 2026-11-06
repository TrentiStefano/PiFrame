import * as os from 'node:os';
import * as fs from 'node:fs';
import { ulid } from 'ulid';
import type { Connection } from '../server/connection.js';
import type { PcpSystemMetricsEvent } from '@piframe/pcp-ts';
import type {
  SystemCpuMetrics,
  SystemMemoryMetrics,
  SystemDiskMetrics,
  SystemGpuMetrics,
  SystemMetricsPayload,
  GpuMetricsProvider
} from './types.js';
import { GpuProviderFactory } from './gpu/GpuProviderFactory.js';

export interface TimerProvider {
  setInterval(fn: () => void, ms: number): NodeJS.Timeout;
  clearInterval(timer: NodeJS.Timeout): void;
}

export interface SystemMetricsServiceOptions {
  intervalMs?: number;
  timerProvider?: TimerProvider;
  gpuProvider?: GpuMetricsProvider;
  gpuFactory?: GpuProviderFactory;
  sampleCpu?: () => Promise<SystemCpuMetrics | null> | SystemCpuMetrics | null;
  sampleMemory?: () => Promise<SystemMemoryMetrics | null> | SystemMemoryMetrics | null;
  sampleDisk?: () => Promise<SystemDiskMetrics | null> | SystemDiskMetrics | null;
}

export class SystemMetricsService {
  private readonly intervalMs: number;
  private readonly timerProvider: TimerProvider;
  private readonly subscribers = new Map<string, Connection>();
  private timer?: NodeJS.Timeout;

  private gpuProvider?: GpuMetricsProvider;
  private readonly gpuFactory: GpuProviderFactory;

  private startPromise?: Promise<void>;
  private stopped = false;

  private readonly sampleCpuFn?: () => Promise<SystemCpuMetrics | null> | SystemCpuMetrics | null;
  private readonly sampleMemoryFn?: () => Promise<SystemMemoryMetrics | null> | SystemMemoryMetrics | null;
  private readonly sampleDiskFn?: () => Promise<SystemDiskMetrics | null> | SystemDiskMetrics | null;

  private lastCpuTimes?: { idle: number; total: number };

  constructor(opts: SystemMetricsServiceOptions = {}) {
    this.intervalMs = opts.intervalMs ?? 1000;
    this.timerProvider = opts.timerProvider ?? {
      setInterval: (fn, ms) => setInterval(fn, ms),
      clearInterval: (t) => clearInterval(t)
    };
    this.gpuProvider = opts.gpuProvider;
    this.gpuFactory = opts.gpuFactory ?? new GpuProviderFactory();
    this.sampleCpuFn = opts.sampleCpu;
    this.sampleMemoryFn = opts.sampleMemory;
    this.sampleDiskFn = opts.sampleDisk;
  }

  public getSubscriberCount(): number {
    return this.subscribers.size;
  }

  public isSampling(): boolean {
    return this.timer !== undefined;
  }

  public async subscribe(conn: Connection): Promise<{ intervalMs: number }> {
    this.stopped = false;
    this.subscribers.set(conn.id, conn);

    await this.startSampling();

    return { intervalMs: this.intervalMs };
  }

  public unsubscribe(connId: string): void {
    const existed = this.subscribers.delete(connId);
    if (existed && this.subscribers.size === 0) {
      this.stopSampling();
    }
  }

  public handleConnectionClose(connId: string): void {
    this.unsubscribe(connId);
  }

  private startSampling(): Promise<void> {
    if (this.timer) {
      return Promise.resolve();
    }
    if (this.startPromise) {
      return this.startPromise;
    }

    this.startPromise = (async () => {
      try {
        if (!this.gpuProvider) {
          const provider = await this.gpuFactory.getProvider();
          this.gpuProvider = provider;
        }

        if (this.stopped || this.subscribers.size === 0) {
          return;
        }

        if (this.timer) {
          return;
        }

        this.gpuProvider.start();

        if (this.stopped || this.subscribers.size === 0) {
          this.gpuProvider.stop();
          return;
        }

        this.timer = this.timerProvider.setInterval(() => {
          void this.tick();
        }, this.intervalMs);
        this.timer.unref?.();
      } catch {
        // Provider resolution or startup failure should not crash daemon
      } finally {
        this.startPromise = undefined;
      }
    })();

    return this.startPromise;
  }

  private stopSampling(): void {
    if (this.timer) {
      this.timerProvider.clearInterval(this.timer);
      this.timer = undefined;
    }
    if (this.gpuProvider) {
      this.gpuProvider.stop();
    }
    this.lastCpuTimes = undefined;
  }

  public stop(): void {
    this.stopped = true;
    this.subscribers.clear();
    this.stopSampling();
  }

  public async tick(): Promise<void> {
    if (this.subscribers.size === 0) {
      this.stopSampling();
      return;
    }

    const [cpu, memory, disk, gpu] = await Promise.all([
      Promise.resolve(this.sampleCpu()),
      Promise.resolve(this.sampleMemory()),
      Promise.resolve(this.sampleDisk()),
      this.sampleGpu()
    ]);

    const payload: SystemMetricsPayload = {
      sampledAt: Date.now(),
      cpu,
      memory,
      disk,
      gpu
    };

    const event: PcpSystemMetricsEvent = {
      protocol: 1,
      kind: 'event',
      id: `ev_${ulid()}`,
      ts: Date.now(),
      sessionId: '@daemon',
      seq: 0,
      type: 'system.metrics',
      payload
    };

    for (const conn of this.subscribers.values()) {
      try {
        conn.send(event);
      } catch {
        // Connection send error ignored
      }
    }
  }

  private sampleCpu(): Promise<SystemCpuMetrics | null> | SystemCpuMetrics | null {
    if (this.sampleCpuFn) {
      return this.sampleCpuFn();
    }
    return this.sampleCpuDefault();
  }

  private sampleCpuDefault(): SystemCpuMetrics | null {
    const cpus = os.cpus();
    if (!cpus || cpus.length === 0) return null;

    let idle = 0;
    let total = 0;
    for (const cpu of cpus) {
      idle += cpu.times.idle;
      total +=
        cpu.times.user +
        cpu.times.nice +
        cpu.times.sys +
        cpu.times.idle +
        cpu.times.irq;
    }

    if (!this.lastCpuTimes) {
      this.lastCpuTimes = { idle, total };
      return null;
    }

    const deltaIdle = idle - this.lastCpuTimes.idle;
    const deltaTotal = total - this.lastCpuTimes.total;
    this.lastCpuTimes = { idle, total };

    if (deltaTotal <= 0) {
      return { percent: 0.0 };
    }

    const rawPercent = ((deltaTotal - deltaIdle) / deltaTotal) * 100;
    const percent = Math.min(100, Math.max(0, Math.round(rawPercent * 10) / 10));
    return { percent };
  }

  private sampleMemory(): Promise<SystemMemoryMetrics | null> | SystemMemoryMetrics | null {
    if (this.sampleMemoryFn) {
      return this.sampleMemoryFn();
    }
    return this.sampleMemoryDefault();
  }

  private sampleMemoryDefault(): SystemMemoryMetrics | null {
    try {
      if (process.platform === 'linux' && fs.existsSync('/proc/meminfo')) {
        const meminfo = fs.readFileSync('/proc/meminfo', 'utf8');
        const totalMatch = meminfo.match(/^MemTotal:\s*(\d+)\s*kB/m);
        const availMatch = meminfo.match(/^MemAvailable:\s*(\d+)\s*kB/m);
        if (totalMatch && availMatch) {
          const totalKb = parseInt(totalMatch[1], 10);
          const availKb = parseInt(availMatch[1], 10);
          if (!isNaN(totalKb) && !isNaN(availKb) && totalKb > 0) {
            const totalBytes = totalKb * 1024;
            const availableBytes = availKb * 1024;
            const usedBytes = Math.max(0, totalBytes - availableBytes);
            const percent = Math.min(
              100,
              Math.max(0, Math.round(((usedBytes / totalBytes) * 100) * 10) / 10)
            );
            return { usedBytes, totalBytes, percent };
          }
        }
      }
    } catch {
      // fallback
    }

    try {
      const totalBytes = os.totalmem();
      const freeBytes = os.freemem();
      if (totalBytes <= 0) return null;
      const usedBytes = Math.max(0, totalBytes - freeBytes);
      const percent = Math.min(
        100,
        Math.max(0, Math.round(((usedBytes / totalBytes) * 100) * 10) / 10)
      );
      return { usedBytes, totalBytes, percent };
    } catch {
      return null;
    }
  }

  private sampleDisk(): Promise<SystemDiskMetrics | null> | SystemDiskMetrics | null {
    if (this.sampleDiskFn) {
      return this.sampleDiskFn();
    }
    return this.sampleDiskDefault();
  }

  private async sampleDiskDefault(): Promise<SystemDiskMetrics | null> {
    try {
      const home = os.homedir();
      const stat = await fs.promises.statfs(home);
      const bsize = BigInt(stat.bsize);
      const blocks = BigInt(stat.blocks);
      const bfree = BigInt(stat.bfree);
      if (blocks <= 0n) return null;

      const totalBig = blocks * bsize;
      const usedBig = (blocks - bfree) * bsize;
      const totalBytes = Number(totalBig);
      const usedBytes = Number(usedBig);
      if (totalBytes <= 0) return null;

      const percent = Math.min(
        100,
        Math.max(0, Math.round(((usedBytes / totalBytes) * 100) * 10) / 10)
      );
      return { usedBytes, totalBytes, percent };
    } catch {
      return null;
    }
  }

  private async sampleGpu(): Promise<SystemGpuMetrics> {
    if (!this.gpuProvider) {
      return {
        percent: null,
        memoryUsedBytes: null,
        memoryTotalBytes: null,
        source: null
      };
    }
    try {
      const sample = await this.gpuProvider.getSample();
      return sample;
    } catch {
      return {
        percent: null,
        memoryUsedBytes: null,
        memoryTotalBytes: null,
        source: this.gpuProvider.source
      };
    }
  }
}
