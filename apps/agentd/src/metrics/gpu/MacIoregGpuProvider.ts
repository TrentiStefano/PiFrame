import { execFile, type ChildProcess } from 'node:child_process';
import type { GpuMetricsProvider, GpuSample } from '../types.js';
import { parseIoregOutput } from '../parsers/ioregParser.js';

export type ExecFileFn = typeof execFile;

export class MacIoregGpuProvider implements GpuMetricsProvider {
  public readonly source = 'ioreg';
  private inFlight = false;
  private currentChild?: ChildProcess;
  private stopped = true;
  private readonly execFileFn: ExecFileFn;
  private latestSample: GpuSample = {
    percent: null,
    memoryUsedBytes: null,
    memoryTotalBytes: null,
    source: 'ioreg'
  };

  constructor(execFileFn: ExecFileFn = execFile) {
    this.execFileFn = execFileFn;
  }

  public start(): void {
    this.stopped = false;
  }

  public stop(): void {
    this.stopped = true;
    if (this.currentChild) {
      const child = this.currentChild;
      this.currentChild = undefined;
      try {
        child.kill();
      } catch {}
    }
    this.inFlight = false;
    this.latestSample = {
      percent: null,
      memoryUsedBytes: null,
      memoryTotalBytes: null,
      source: 'ioreg'
    };
  }

  public async getSample(): Promise<GpuSample> {
    if (this.stopped) {
      return this.latestSample;
    }
    if (this.inFlight) {
      // Skip a tick if previous call is still running
      return this.latestSample;
    }

    this.inFlight = true;

    return new Promise<GpuSample>((resolve) => {
      try {
        let child: ChildProcess | undefined;
        child = this.execFileFn(
          'ioreg',
          ['-r', '-d', '1', '-w', '0', '-c', 'IOAccelerator'],
          { timeout: 800, shell: false, windowsHide: true },
          (err, stdout) => {
            this.inFlight = false;
            if (this.currentChild === child) {
              this.currentChild = undefined;
            }
            if (this.stopped) {
              resolve(this.latestSample);
              return;
            }
            if (err || !stdout) {
              resolve(this.latestSample);
              return;
            }
            this.latestSample = parseIoregOutput(stdout);
            resolve(this.latestSample);
          }
        );
        if (this.inFlight) {
          this.currentChild = child;
        }
      } catch {
        this.inFlight = false;
        this.currentChild = undefined;
        resolve(this.latestSample);
      }
    });
  }
}
