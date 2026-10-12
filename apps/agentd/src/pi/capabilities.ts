import * as fs from 'node:fs';
import type { PiCapabilities } from './piCommands.js';
import { StdioPiTransport } from './StdioPiTransport.js';

interface CachedCapability {
  mtime: number;
  caps: PiCapabilities;
}

const capsCache = new Map<string, CachedCapability>();

export async function probeCapabilities(executablePath: string, version: string, isSupported: boolean): Promise<PiCapabilities> {
  const defaultCaps: PiCapabilities = {
    version,
    supported: isSupported,
    modes: ['rpc'],
    features: ['thinking', 'tools', 'compaction'],
    thinkingLevels: ['none', 'low', 'medium', 'high']
  };

  if (!isSupported) {
    return { ...defaultCaps, supported: false };
  }

  try {
    const stat = fs.statSync(executablePath);
    const cached = capsCache.get(executablePath);
    if (cached && cached.mtime === stat.mtimeMs) {
      return cached.caps;
    }

    // Ephemeral RPC probe with --no-session
    const transport = new StdioPiTransport({
      executablePath,
      capabilities: defaultCaps
    });

    await transport.start({
      cwd: process.cwd(),
      args: ['--mode', 'rpc', '--no-session', '--no-extensions', '--no-skills', '--no-prompt-templates', '--offline']
    });

    let thinkingLevels: string[] = ['none', 'low', 'medium', 'high'];

    try {
      const resp = await transport.send({ command: 'get_available_thinking_levels' });
      if (resp.success && Array.isArray(resp.data?.levels)) {
        thinkingLevels = resp.data.levels;
      }
    } catch {}

    await transport.stop({ graceMs: 1000 });

    const finalCaps: PiCapabilities = {
      version,
      supported: true,
      modes: ['rpc'],
      features: ['thinking', 'tools', 'compaction', 'subagents'],
      thinkingLevels
    };

    capsCache.set(executablePath, {
      mtime: stat.mtimeMs,
      caps: finalCaps
    });

    return finalCaps;
  } catch {
    return defaultCaps;
  }
}
