import { spawn, type ChildProcess } from 'node:child_process';
import type { GpuMetricsProvider, GpuSample } from '../types.js';
import { parseNvidiaSmiLine, aggregateNvidiaSmiSamples, type RawNvidiaSample } from '../parsers/nvidiaSmiParser.js';

export type SpawnChildProcessFn = typeof spawn;

export class NvidiaGpuProvider implements GpuMetricsProvider {
  public readonly source = 'nvidia-smi';
  private child?: ChildProcess;
  private currentSamples: RawNvidiaSample[] = [];
  private latestSample: GpuSample = {
    percent: null,
    memoryUsedBytes: null,
    memoryTotalBytes: null,
    source: 'nvidia-smi'
  };
  private stdoutBuffer = '';
  private stopped = true;
  private readonly spawnFn: SpawnChildProcessFn;

  constructor(spawnFn: SpawnChildProcessFn = spawn) {
    this.spawnFn = spawnFn;
  }

  public start(): void {
    this.stopped = false;
    if (this.child) return;

    try {
      const child = this.spawnFn(
        'nvidia-smi',
        [
          '--query-gpu=utilization.gpu,memory.used,memory.total',
          '--format=csv,noheader,nounits',
          '-l',
          '1'
        ],
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
          const parsed = parseNvidiaSmiLine(line);
          if (parsed) {
            this.currentSamples.push(parsed);
          }
        }
      });

      child.on('error', () => {
        if (this.stopped || this.child !== child) return;
        this.stopChild();
      });

      child.on('exit', () => {
        if (this.stopped || this.child !== child) return;
        this.stopChild();
      });
    } catch {
      this.stopChild();
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
    this.currentSamples = [];
    this.stdoutBuffer = '';
    this.latestSample = {
      percent: null,
      memoryUsedBytes: null,
      memoryTotalBytes: null,
      source: 'nvidia-smi'
    };
  }

  public getSample(): GpuSample {
    if (this.stopped) {
      return this.latestSample;
    }
    if (this.currentSamples.length > 0) {
      this.latestSample = aggregateNvidiaSmiSamples(this.currentSamples);
      this.currentSamples = [];
    }
    return this.latestSample;
  }
}
