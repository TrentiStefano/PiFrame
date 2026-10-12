import * as fs from 'node:fs';
import * as path from 'node:path';

export interface PiLaunchCommand {
  file: string;
  args: string[];
}

/** Resolve Node entrypoints and Windows npm shims without invoking a shell. */
export function resolvePiLaunch(executablePath: string, args: string[] = [], platform = process.platform): PiLaunchCommand {
  const extension = path.extname(executablePath).toLowerCase();
  if (['.js', '.cjs', '.mjs'].includes(extension)) {
    return { file: process.execPath, args: [executablePath, ...args] };
  }

  if (platform === 'win32' && ['.cmd', '.bat'].includes(extension)) {
    const adjacentCli = path.join(
      path.dirname(executablePath),
      'node_modules', '@earendil-works', 'pi-coding-agent', 'dist', 'bundle', 'cli.js'
    );
    if (fs.existsSync(adjacentCli)) {
      return { file: process.execPath, args: [adjacentCli, ...args] };
    }
  }

  return { file: executablePath, args: [...args] };
}
