import type { GpuMetricsProvider, GpuSample } from '../types.js';

export class NullGpuProvider implements GpuMetricsProvider {
  public readonly source = null;
  public start(): void {}
  public stop(): void {}
  public getSample(): GpuSample {
    return {
      percent: null,
      memoryUsedBytes: null,
      memoryTotalBytes: null,
      source: null
    };
  }
}
