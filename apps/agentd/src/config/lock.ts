import * as fs from 'node:fs';
import * as path from 'node:path';
import { getRuntimeDir } from './runtime.js';

export interface LockHandle {
  release: () => void;
}

export function isPidAlive(pid: number): boolean {
  if (!pid || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err: any) {
    return err.code === 'EPERM'; // Process exists but lacks permission to signal
  }
}

export function getLockFilePath(): string {
  return path.join(getRuntimeDir(), 'daemon.lock');
}

export function acquireSingleInstanceLock(): LockHandle | null {
  const lockFile = getLockFilePath();

  if (fs.existsSync(lockFile)) {
    try {
      const existingPid = parseInt(fs.readFileSync(lockFile, 'utf8').trim(), 10);
      if (isPidAlive(existingPid)) {
        // Another instance is actively running
        return null;
      }
      // Process is stale; clean up
      fs.unlinkSync(lockFile);
    } catch {
      // Corrupt lock file, remove it
      try { fs.unlinkSync(lockFile); } catch {}
    }
  }

  // Attempt to write our PID exclusively
  try {
    fs.writeFileSync(lockFile, String(process.pid), { flag: 'wx', encoding: 'utf8' });
  } catch (err: any) {
    if (err.code === 'EEXIST') {
      // Race condition: another process just created it
      return null;
    }
    throw err;
  }

  return {
    release: () => {
      try {
        if (fs.existsSync(lockFile)) {
          const pid = parseInt(fs.readFileSync(lockFile, 'utf8').trim(), 10);
          if (pid === process.pid) {
            fs.unlinkSync(lockFile);
          }
        }
      } catch {}
    }
  };
}
