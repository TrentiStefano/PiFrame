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
    // 1. Check for adjacent launcher (e.g. ~/.pi/agent/bin/pi-launcher.js)
    const adjacentLauncher = path.join(path.dirname(executablePath), 'pi-launcher.js');
    if (fs.existsSync(adjacentLauncher)) {
      return { file: process.execPath, args: [adjacentLauncher, ...args] };
    }

    // 2. Check for npm package dist bundle
    const adjacentCli = path.join(
      path.dirname(executablePath),
      'node_modules', '@earendil-works', 'pi-coding-agent', 'dist', 'bundle', 'cli.js'
    );
    if (fs.existsSync(adjacentCli)) {
      return { file: process.execPath, args: [adjacentCli, ...args] };
    }

    // 3. Parse shim script to extract target node script
    try {
      const content = fs.readFileSync(executablePath, 'utf8');
      const match = content.match(/node(?:\.exe)?\s+["']?([^"'\r\n]+\.c?js)["']?/i);
      if (match && match[1]) {
        let resolved = match[1].replace(/%~dp0/gi, path.dirname(executablePath) + path.sep);
        resolved = path.resolve(path.dirname(executablePath), resolved);
        if (fs.existsSync(resolved)) {
          return { file: process.execPath, args: [resolved, ...args] };
        }
      }
    } catch {}

    // 4. Fallback for Windows .cmd/.bat: wrap via cmd.exe to avoid libuv spawn EINVAL
    const comSpec = process.env.ComSpec || 'cmd.exe';
    return { file: comSpec, args: ['/d', '/s', '/c', executablePath, ...args] };
  }

  return { file: executablePath, args: [...args] };
}
