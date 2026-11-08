import type {
  SystemCpuMetrics,
  SystemMemoryMetrics,
  SystemDiskMetrics,
  SystemGpuMetrics,
  SystemGpuSource,
  SystemMetricsPayload
} from '@piframe/pcp-ts';

export type {
  SystemCpuMetrics,
  SystemMemoryMetrics,
  SystemDiskMetrics,
  SystemGpuMetrics,
  SystemGpuSource,
  SystemMetricsPayload
};

export interface GpuSample {
  percent: number | null;
  memoryUsedBytes: number | null;
  memoryTotalBytes: number | null;
  source: SystemGpuSource;
}

export interface GpuMetricsProvider {
  readonly source: SystemGpuSource;
  start(): void;
  stop(): void;
  getSample(): Promise<GpuSample> | GpuSample;
}
