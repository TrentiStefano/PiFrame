import { execFile } from 'node:child_process';
import type { GpuMetricsProvider } from '../types.js';
import { NvidiaGpuProvider } from './NvidiaGpuProvider.js';
import { WindowsTypeperfGpuProvider } from './WindowsTypeperfGpuProvider.js';
import { LinuxSysfsGpuProvider } from './LinuxSysfsGpuProvider.js';
import { MacIoregGpuProvider } from './MacIoregGpuProvider.js';
import { NullGpuProvider } from './NullGpuProvider.js';

export type DetectedGpuKind = 'nvidia-smi' | 'typeperf' | 'sysfs' | 'ioreg' | 'none';

export async function probeNvidiaSmi(): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    try {
      execFile('nvidia-smi', ['-L'], { timeout: 1500, shell: false, windowsHide: true }, (err, stdout) => {
        if (!err && stdout && stdout.length > 0) {
          resolve(true);
        } else {
          resolve(false);
        }
      });
    } catch {
      resolve(false);
    }
  });
}

export class GpuProviderFactory {
  private cachedKind?: DetectedGpuKind;
  private cachedProvider?: GpuMetricsProvider;

  public async getProvider(platform: NodeJS.Platform = process.platform): Promise<GpuMetricsProvider> {
    if (this.cachedProvider) {
      return this.cachedProvider;
    }

    if (!this.cachedKind) {
      const hasNvidia = await probeNvidiaSmi();
      if (hasNvidia) {
        this.cachedKind = 'nvidia-smi';
      } else if (platform === 'win32') {
        this.cachedKind = 'typeperf';
      } else if (platform === 'linux') {
        this.cachedKind = 'sysfs';
      } else if (platform === 'darwin') {
        this.cachedKind = 'ioreg';
      } else {
        this.cachedKind = 'none';
      }
    }

    switch (this.cachedKind) {
      case 'nvidia-smi':
        this.cachedProvider = new NvidiaGpuProvider();
        break;
      case 'typeperf':
        this.cachedProvider = new WindowsTypeperfGpuProvider();
        break;
      case 'sysfs':
        this.cachedProvider = new LinuxSysfsGpuProvider();
        break;
      case 'ioreg':
        this.cachedProvider = new MacIoregGpuProvider();
        break;
      default:
        this.cachedProvider = new NullGpuProvider();
        break;
    }

    return this.cachedProvider;
  }
}
