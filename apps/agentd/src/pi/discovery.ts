import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import type { PiCapabilities } from './piCommands.js';
import { resolvePiLaunch } from './executable.js';
import { getAugmentedPath, getAugmentedEnv } from './env.js';

const execFileAsync = promisify(execFile);

export interface PiInstallation {
  found: boolean;
  path?: string;
  version?: string;
  supported: boolean;
  error?: string;
  hint?: string;
}

export const MINIMUM_PI_VERSION = '0.85.0';

export function compareSemver(a: string, b: string): number {
  const parse = (v: string) => v.replace(/^v/, '').split('-')[0].split('.').map(n => parseInt(n, 10) || 0);
  const pa = parse(a);
  const pb = parse(b);
  for (let i = 0; i < 3; i++) {
    const na = pa[i] ?? 0;
    const nb = pb[i] ?? 0;
    if (na > nb) return 1;
    if (na < nb) return -1;
  }
  return 0;
}

export async function discoverPi(customPath?: string): Promise<PiInstallation> {
  const candidates: string[] = [];

  // 1. Explicit config path
  if (customPath && customPath.trim()) {
    candidates.push(customPath.trim());
  }

  // 2. PI_FRAME_PI_PATH environment variable
  if (process.env.PI_FRAME_PI_PATH) {
    candidates.push(process.env.PI_FRAME_PI_PATH);
  }

  // 3. Known well-known locations
  if (process.platform === 'win32') {
    const appdata = process.env.APPDATA;
    const localappdata = process.env.LOCALAPPDATA;
    if (appdata) candidates.push(path.join(appdata, 'npm', 'pi.cmd'));
    if (localappdata) candidates.push(path.join(localappdata, 'npm', 'pi.cmd'));
    // Common nvm4w or node default global paths
    candidates.push('C:\\nvm4w\\nodejs\\node_modules\\@earendil-works\\pi-coding-agent\\dist\\bundle\\cli.js');
  } else {
    candidates.push(path.join(os.homedir(), '.local', 'bin', 'pi'));
    candidates.push('/usr/local/bin/pi');
    candidates.push('/opt/homebrew/bin/pi');
  }

  // 4. PATH lookup
  const pathEnv = getAugmentedPath();
  const pathDirs = pathEnv.split(path.delimiter);
  const binaryNames = process.platform === 'win32' ? ['pi.cmd', 'pi.exe', 'pi.bat', 'pi'] : ['pi'];

  for (const dir of pathDirs) {
    for (const bin of binaryNames) {
      candidates.push(path.join(dir, bin));
    }
  }

  let foundPath: string | undefined;

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      try {
        const stat = fs.statSync(candidate);
        if (stat.isFile()) {
          foundPath = candidate;
          break;
        }
      } catch {}
    }
  }

  if (!foundPath) {
    return {
      found: false,
      supported: false,
      error: 'PI_NOT_FOUND',
      hint: 'Installa Pi (npm install -g @earendil-works/pi-coding-agent) o specifica il percorso nelle impostazioni.'
    };
  }

  // Probe pi --version
  try {
    const launch = resolvePiLaunch(foundPath, ['--version']);
    const { stdout } = await execFileAsync(launch.file, launch.args, {
      timeout: 5000,
      windowsHide: true,
      env: getAugmentedEnv()
    });

    const rawVersion = stdout.trim().match(/\d+\.\d+\.\d+/)?.[0];
    if (!rawVersion) {
      return {
        found: true,
        path: foundPath,
        supported: false,
        error: 'PI_VERSION_UNPARSEABLE',
        hint: `Impossibile determinare la versione di Pi da: "${stdout.trim()}"`
      };
    }

    const isSupported = compareSemver(rawVersion, MINIMUM_PI_VERSION) >= 0;

    return {
      found: true,
      path: foundPath,
      version: rawVersion,
      supported: isSupported,
      error: isSupported ? undefined : 'PI_VERSION_UNSUPPORTED',
      hint: isSupported ? undefined : `Versione ${rawVersion} rilevata. Richiesta >= ${MINIMUM_PI_VERSION}. Aggiorna Pi.`
    };
  } catch (err: any) {
    return {
      found: true,
      path: foundPath,
      supported: false,
      error: 'PI_EXECUTION_FAILED',
      hint: `Errore durante l'esecuzione di ${foundPath} --version: ${err.message}`
    };
  }
}
