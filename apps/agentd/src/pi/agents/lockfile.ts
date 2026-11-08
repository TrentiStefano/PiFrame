import * as fs from 'node:fs';
import * as path from 'node:path';

export interface LockOptions {
  staleMs?: number;
  maxAttempts?: number;
  delayMs?: number;
  updateIntervalMs?: number;
}

export const DEFAULT_LOCK_OPTIONS: Required<LockOptions> = {
  staleMs: 10_000,
  maxAttempts: 25,
  delayMs: 25,
  updateIntervalMs: 5_000,
};

export function getLockfilePath(filePath: string): string {
  return `${filePath}.lock`;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export interface LockHandle {
  (): void;
  release: () => void;
  check: () => void;
  isCompromised: () => boolean;
}

/**
 * Pi-compatible directory-based lock matching proper-lockfile 4.x semantics:
 * - Lock path is `<filePath>.lock`
 * - Atomicity via fs.mkdirSync
 * - Stale lock detected via directory mtime < Date.now() - staleMs
 * - Records lock dir mtime at acquisition and refreshes periodically (setInterval ~ stale/2, unref)
 * - On release, only rmdirs if the dir's current mtime equals our last recorded mtime (tolerance < 1ms)
 * - Never deletes a lock we don't own
 * - check() asserts ownership right before rename/commit and throws AGENTS_CONFIG_LOCKED if compromised
 */
export async function acquireLock(
  filePath: string,
  options: LockOptions = {}
): Promise<LockHandle> {
  const staleMs = options.staleMs ?? DEFAULT_LOCK_OPTIONS.staleMs;
  const maxAttempts = options.maxAttempts ?? DEFAULT_LOCK_OPTIONS.maxAttempts;
  const delayMs = options.delayMs ?? DEFAULT_LOCK_OPTIONS.delayMs;
  const updateIntervalMs =
    options.updateIntervalMs ?? Math.max(10, Math.floor(staleMs / 2));
  const lockfilePath = getLockfilePath(filePath);

  // Ensure parent directory exists
  const parentDir = path.dirname(filePath);
  if (!fs.existsSync(parentDir)) {
    fs.mkdirSync(parentDir, { recursive: true });
  }

  let attempt = 0;
  while (attempt < maxAttempts) {
    attempt++;
    try {
      fs.mkdirSync(lockfilePath);
      // Lock acquired successfully
      const stat = fs.statSync(lockfilePath);
      let lastMtime = stat.mtimeMs;
      let released = false;
      let compromised = false;

      // Refresh periodic timer while held
      const timer = setInterval(() => {
        if (released || compromised) return;
        try {
          const curStat = fs.statSync(lockfilePath);
          if (Math.abs(curStat.mtimeMs - lastMtime) >= 1) {
            compromised = true;
            clearInterval(timer);
            return;
          }
          const now = new Date();
          fs.utimesSync(lockfilePath, now, now);
          lastMtime = fs.statSync(lockfilePath).mtimeMs;
        } catch {
          compromised = true;
          clearInterval(timer);
        }
      }, updateIntervalMs);
      timer.unref();

      const checkOwnership = () => {
        if (compromised) {
          const error = new Error(`Lock for ${path.basename(filePath)} was compromised or stolen`);
          throw Object.assign(error, { code: 'AGENTS_CONFIG_LOCKED' });
        }
        try {
          const curStat = fs.statSync(lockfilePath);
          if (Math.abs(curStat.mtimeMs - lastMtime) >= 1) {
            compromised = true;
            clearInterval(timer);
            const error = new Error(`Lock for ${path.basename(filePath)} was compromised or stolen`);
            throw Object.assign(error, { code: 'AGENTS_CONFIG_LOCKED' });
          }
        } catch {
          compromised = true;
          clearInterval(timer);
          const error = new Error(`Lock for ${path.basename(filePath)} was removed`);
          throw Object.assign(error, { code: 'AGENTS_CONFIG_LOCKED' });
        }
      };

      const release = () => {
        if (released) return;
        released = true;
        clearInterval(timer);

        if (compromised) {
          // Never delete a lock we don't own!
          return;
        }

        try {
          const curStat = fs.statSync(lockfilePath);
          if (Math.abs(curStat.mtimeMs - lastMtime) < 1) {
            fs.rmdirSync(lockfilePath);
          }
        } catch {
          // Ignore ENOENT or already removed
        }
      };

      const handle: any = () => release();
      handle.release = release;
      handle.check = checkOwnership;
      handle.isCompromised = () => compromised;

      return handle as LockHandle;
    } catch (err: any) {
      if (err?.code !== 'EEXIST') {
        throw err;
      }

      // Check if existing lock is stale
      try {
        const stat = fs.statSync(lockfilePath);
        const mtime = stat.mtimeMs || stat.mtime.getTime();
        const age = Date.now() - mtime;
        if (age > staleMs) {
          // Lock is stale: remove it and retry immediately without sleeping
          try {
            fs.rmdirSync(lockfilePath);
          } catch {
            // Already removed by another process
          }
          continue;
        }
      } catch (statErr: any) {
        // Lock might have been released between mkdir and stat
        if (statErr?.code === 'ENOENT') {
          continue;
        }
      }

      if (attempt >= maxAttempts) {
        break;
      }
      await sleep(delayMs);
    }
  }

  const error = new Error(`Failed to acquire settings lock for ${path.basename(filePath)}`);
  throw Object.assign(error, { code: 'AGENTS_CONFIG_LOCKED' });
}

export async function withFileLock<T>(
  filePath: string,
  fn: (lock: LockHandle) => Promise<T> | T,
  options?: LockOptions
): Promise<T> {
  const lock = await acquireLock(filePath, options);
  try {
    return await fn(lock);
  } finally {
    lock.release();
  }
}

