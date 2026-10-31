import * as os from 'node:os';
import * as path from 'node:path';

let cachedAugmentedPath: string | null = null;

/**
 * Returns an augmented PATH string containing standard tool directories
 * across macOS (Homebrew, /usr/local, ~/.local/bin), Linux, and Windows.
 */
export function getAugmentedPath(): string {
  if (cachedAugmentedPath) return cachedAugmentedPath;

  const currentPath = process.env.PATH || '';
  const delimiter = path.delimiter;
  const dirs = currentPath.split(delimiter).filter(Boolean);
  const seen = new Set(dirs);

  function addDir(dir: string): void {
    if (!dir || seen.has(dir)) return;
    dirs.unshift(dir);
    seen.add(dir);
  }

  if (process.platform !== 'win32') {
    addDir('/opt/homebrew/bin');
    addDir('/opt/homebrew/sbin');
    addDir('/usr/local/bin');
    addDir('/usr/local/sbin');
    addDir(path.join(os.homedir(), '.local', 'bin'));
    addDir(path.join(os.homedir(), '.local', 'share', 'pi-node', 'current', 'bin'));
    addDir(path.join(os.homedir(), '.cargo', 'bin'));
    addDir(path.join(os.homedir(), '.bun', 'bin'));
    try {
      addDir(path.dirname(process.execPath));
    } catch {}
  } else {
    const appdata = process.env.APPDATA;
    const localappdata = process.env.LOCALAPPDATA;
    if (appdata) addDir(path.join(appdata, 'npm'));
    if (localappdata) addDir(path.join(localappdata, 'npm'));
    addDir(path.join(os.homedir(), '.local', 'bin'));
    try {
      addDir(path.dirname(process.execPath));
    } catch {}
  }

  cachedAugmentedPath = dirs.join(delimiter);
  return cachedAugmentedPath;
}

/**
 * Returns a cloned process.env with augmented PATH.
 */
export function getAugmentedEnv(extra?: Record<string, string | undefined>): NodeJS.ProcessEnv {
  return {
    ...process.env,
    PATH: getAugmentedPath(),
    ...extra
  };
}
