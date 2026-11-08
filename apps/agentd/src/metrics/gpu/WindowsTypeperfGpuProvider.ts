import { spawn, type ChildProcess } from 'node:child_process';
import type { GpuMetricsProvider, GpuSample } from '../types.js';
import {
  parseTypeperfHeader,
  parseTypeperfRow,
  isTypeperfHeaderLine,
  type TypeperfColumnMapping
} from '../parsers/typeperfParser.js';

export type SpawnChildProcessFn = typeof spawn;

export class WindowsTypeperfGpuProvider implements GpuMetricsProvider {
  public readonly source = 'typeperf';
  private child?: ChildProcess;
  private headerMappings: TypeperfColumnMapping[] = [];
  private latestPercent: number | null = null;
  private stdoutBuffer = '';
  private retryCount = 0;
  private permanentlyFailed = false;
  private stopped = true;
  private readonly spawnFn: SpawnChildProcessFn;

  constructor(spawnFn: SpawnChildProcessFn = spawn) {
    this.spawnFn = spawnFn;
  }

  public start(): void {
    this.stopped = false;
    if (this.child || this.permanentlyFailed) return;
    this.spawnChild();
  }

  private spawnChild(): void {
    if (this.stopped || this.permanentlyFailed) return;
    try {
      const child = this.spawnFn(
        'typeperf',
        ['\\GPU Engine(*)\\Utilization Percentage', '-si', '1'],
        {
          shell: false,
          windowsHide: true,
          stdio: ['ignore', 'pipe', 'ignore']
        }
      );
      this.child = child;

      child.stdout?.setEncoding('utf8');
      child.stdout?.on('data', (chunk: string) => {
        if (this.stopped || this.child !== child) return;
        this.stdoutBuffer += chunk;
        const lines = this.stdoutBuffer.split(/\r?\n/);
        this.stdoutBuffer = lines.pop() ?? '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed) continue;

          if (this.headerMappings.length === 0 && isTypeperfHeaderLine(trimmed)) {
            this.headerMappings = parseTypeperfHeader(trimmed);
          } else if (this.headerMappings.length > 0) {
            const parsed = parseTypeperfRow(trimmed, this.headerMappings);
            if (parsed !== null) {
              this.latestPercent = parsed;
            }
          }
        }
      });

      child.on('error', () => {
        if (this.stopped || this.child !== child) return;
        this.handleFailure();
      });

      child.on('exit', (code) => {
        if (this.stopped || this.child !== child) return;
        if (code !== 0 && code !== null) {
          this.handleFailure();
        } else {
          this.stopChild();
        }
      });
    } catch {
      this.handleFailure();
    }
  }

  private handleFailure(): void {
    if (this.stopped) return;
    this.stopChild();
    this.latestPercent = null;
    if (this.stopped) return;
    if (this.retryCount < 1) {
      this.retryCount++;
      this.spawnChild();
    } else {
      this.permanentlyFailed = true;
    }
  }

  private stopChild(): void {
    if (this.child) {
      const child = this.child;
      this.child = undefined;
      try {
        child.kill();
      } catch {}
    }
  }

  public stop(): void {
    this.stopped = true;
    this.stopChild();
    this.headerMappings = [];
    this.stdoutBuffer = '';
    this.latestPercent = null;
    this.retryCount = 0;
    this.permanentlyFailed = false;
  }

  public getSample(): GpuSample {
    return {
      percent: this.stopped ? null : this.latestPercent,
      memoryUsedBytes: null,
      memoryTotalBytes: null,
      source: 'typeperf'
    };
  }
}
