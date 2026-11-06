import * as fs from 'node:fs';
import * as path from 'node:path';
import type { GpuMetricsProvider, GpuSample } from '../types.js';
import { parseSysfsCard, aggregateSysfsCards, type RawSysfsCard } from '../parsers/sysfsParser.js';

export class LinuxSysfsGpuProvider implements GpuMetricsProvider {
  public readonly source = 'sysfs';
  private drmDir: string;

  constructor(drmDir = '/sys/class/drm') {
    this.drmDir = drmDir;
  }

  public start(): void {}
  public stop(): void {}

  public async getSample(): Promise<GpuSample> {
    try {
      if (!fs.existsSync(this.drmDir)) {
        return { percent: null, memoryUsedBytes: null, memoryTotalBytes: null, source: 'sysfs' };
      }

      const entries = await fs.promises.readdir(this.drmDir);
      const cardDirs = entries.filter((name) => /^card\d+$/i.test(name));
      if (cardDirs.length === 0) {
        return { percent: null, memoryUsedBytes: null, memoryTotalBytes: null, source: 'sysfs' };
      }

      const cards: RawSysfsCard[] = [];
      for (const card of cardDirs) {
        const deviceDir = path.join(this.drmDir, card, 'device');
        const busyPath = path.join(deviceDir, 'gpu_busy_percent');
        const vramUsedPath = path.join(deviceDir, 'mem_info_vram_used');
        const vramTotalPath = path.join(deviceDir, 'mem_info_vram_total');

        let busyStr: string | null = null;
        try {
          busyStr = await fs.promises.readFile(busyPath, 'utf8');
        } catch {}

        let vramUsedStr: string | null = null;
        try {
          vramUsedStr = await fs.promises.readFile(vramUsedPath, 'utf8');
        } catch {}

        let vramTotalStr: string | null = null;
        try {
          vramTotalStr = await fs.promises.readFile(vramTotalPath, 'utf8');
        } catch {}

        if (busyStr !== null || vramUsedStr !== null || vramTotalStr !== null) {
          cards.push(parseSysfsCard(busyStr, vramUsedStr, vramTotalStr));
        }
      }

      return aggregateSysfsCards(cards);
    } catch {
      return { percent: null, memoryUsedBytes: null, memoryTotalBytes: null, source: 'sysfs' };
    }
  }
}
