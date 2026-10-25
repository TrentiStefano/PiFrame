import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';

export interface JournalConfig {
  maxEvents: number;
  maxBytes: number;
  snapshotEvery: number;
  retentionHours: number;
}

export interface WorkerConfig {
  idleTimeoutMs: number;
}

export interface LogConfig {
  level: 'debug' | 'info' | 'warn' | 'error';
}

export interface WebConfig {
  enabled: boolean;
  origins: string[];
}

export type RemoteMode = 'view' | 'control';

export interface RemoteConfig {
  enabled: boolean;
  tunnelProvider: 'cloudflared' | 'tailscale' | 'custom';
  /** Command (argv-style, NO shell) that exposes the remote listener. `$PORT` is replaced with the listener port. */
  customTunnelCommand?: string;
  /** Public https URL of the custom tunnel. */
  customTunnelUrl?: string;
  /** Mode assigned to newly paired devices. 'view' unless the desktop user changes it. */
  defaultMode: RemoteMode;
  /** Dedicated port for the remote listener (1024-65535). 0 or undefined = ephemeral port. */
  listenerPort?: number;
}

const REMOTE_PATCH_KEYS = new Set([
  'enabled',
  'tunnelProvider',
  'customTunnelCommand',
  'customTunnelUrl',
  'defaultMode',
  'listenerPort'
]);

function configInvalid(message: string): Error {
  return Object.assign(new Error(message), { code: 'CONFIG_INVALID' });
}

/**
 * Validates a custom tunnel URL. Must be https, without credentials, and must not point at loopback
 * or the unspecified address (otherwise the Host allow-list would trust loopback Host headers).
 * Returns the normalized origin.
 */
export function validateCustomTunnelUrl(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > 300) {
    throw configInvalid('customTunnelUrl must be a non-empty string.');
  }
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw configInvalid('customTunnelUrl is not a valid URL.');
  }
  if (parsed.protocol !== 'https:') throw configInvalid('customTunnelUrl must use https.');
  if (parsed.username || parsed.password) throw configInvalid('customTunnelUrl must not contain credentials.');
  const host = parsed.hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (
    host === 'localhost' || host.endsWith('.localhost') ||
    host === '0.0.0.0' || host === '::' || host === '::1' ||
    /^127\./.test(host) || /^::ffff:127\./.test(host)
  ) {
    throw configInvalid('customTunnelUrl must not point to a loopback address.');
  }
  return parsed.origin;
}

export function validateCustomTunnelCommand(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > 500 || /[\x00\r\n]/.test(value)) {
    throw configInvalid('customTunnelCommand must be a single-line string (max 500 chars).');
  }
  return value;
}

/** Strict whitelist validation for any patch of the `remote` config section. */
export function validateRemotePatch(patch: unknown): Partial<RemoteConfig> {
  if (!patch || typeof patch !== 'object' || Array.isArray(patch)) {
    throw configInvalid('remote config patch must be an object.');
  }
  const out: Partial<RemoteConfig> = {};
  for (const [key, value] of Object.entries(patch as Record<string, unknown>)) {
    if (!REMOTE_PATCH_KEYS.has(key)) throw configInvalid(`Unknown remote config key: ${key}`);
    if (value === undefined) continue;
    switch (key) {
      case 'enabled':
        if (typeof value !== 'boolean') throw configInvalid('remote.enabled must be a boolean.');
        out.enabled = value;
        break;
      case 'tunnelProvider':
        if (value !== 'cloudflared' && value !== 'tailscale' && value !== 'custom') throw configInvalid('remote.tunnelProvider is invalid.');
        out.tunnelProvider = value;
        break;
      case 'defaultMode':
        if (value !== 'view' && value !== 'control') throw configInvalid('remote.defaultMode is invalid.');
        out.defaultMode = value;
        break;
      case 'customTunnelUrl':
        out.customTunnelUrl = value === null || value === '' ? undefined : validateCustomTunnelUrl(value);
        break;
      case 'customTunnelCommand':
        out.customTunnelCommand = value === null || value === '' ? undefined : validateCustomTunnelCommand(value);
        break;
      case 'listenerPort':
        if (value === null || value === '' || value === 0) {
          out.listenerPort = undefined;
        } else if (typeof value !== 'number' || !Number.isInteger(value) || value < 1024 || value > 65535) {
          throw configInvalid('remote.listenerPort must be an integer between 1024 and 65535.');
        } else {
          out.listenerPort = value;
        }
        break;
    }
  }
  return out;
}

export interface DaemonConfig {
  piPath?: string;
  workerIdleTimeoutMs: number;
  journal: JournalConfig;
  log: LogConfig;
  web: WebConfig;
  remote: RemoteConfig;
}

export const DEFAULT_CONFIG: DaemonConfig = {
  workerIdleTimeoutMs: 30 * 60 * 1000, // D9: 30 minutes
  journal: {
    maxEvents: 2000,                    // D7: 2000 events
    maxBytes: 8 * 1024 * 1024,          // D7: 8 MB
    snapshotEvery: 500,                 // D7: snapshot every 500
    retentionHours: 24                  // D7: 24 hours
  },
  log: {
    level: 'info'
  },
  web: {
    enabled: true,
    origins: ['http://127.0.0.1', 'http://localhost']
  },
  remote: {
    enabled: false,
    tunnelProvider: 'cloudflared',
    defaultMode: 'view'
  }
};

export function getPiFrameBaseDir(): string {
  if (process.env.PI_FRAME_HOME) {
    return path.resolve(process.env.PI_FRAME_HOME);
  }
  return path.join(os.homedir(), '.piframe');
}

export function getConfigFilePath(): string {
  return path.join(getPiFrameBaseDir(), 'config.json');
}

/** Config on disk is untrusted input: drop anything that does not validate (fail closed). */
function sanitizeLoadedRemote(raw: unknown): RemoteConfig {
  const base: RemoteConfig = { ...DEFAULT_CONFIG.remote };
  if (!raw || typeof raw !== 'object') return base;
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    try {
      Object.assign(base, validateRemotePatch({ [key]: value }));
    } catch {
      // ignore invalid/legacy keys (e.g. allowFileEdits, readOnly)
    }
  }
  return base;
}

export function loadConfig(): DaemonConfig {
  const configFile = getConfigFilePath();
  if (!fs.existsSync(configFile)) {
    return { ...DEFAULT_CONFIG };
  }
  try {
    const raw = fs.readFileSync(configFile, 'utf8');
    const parsed = JSON.parse(raw);
    return {
      ...DEFAULT_CONFIG,
      ...parsed,
      workerIdleTimeoutMs: parsed.workerIdleTimeoutMs ?? DEFAULT_CONFIG.workerIdleTimeoutMs,
      journal: { ...DEFAULT_CONFIG.journal, ...(parsed.journal || {}) },
      log: { ...DEFAULT_CONFIG.log, ...(parsed.log || {}) },
      web: { ...DEFAULT_CONFIG.web, ...(parsed.web || {}) },
      remote: sanitizeLoadedRemote(parsed.remote)
    };
  } catch (err) {
    console.error(`Failed to read ${configFile}, using default config:`, err);
    return { ...DEFAULT_CONFIG };
  }
}

export function saveConfig(config: DaemonConfig): void {
  const baseDir = getPiFrameBaseDir();
  fs.mkdirSync(baseDir, { recursive: true });
  const configFile = getConfigFilePath();
  const tempFile = `${configFile}.tmp.${process.pid}.${Date.now()}`;

  // Atomic write: write to temp file then rename (owner-only permissions)
  fs.writeFileSync(tempFile, JSON.stringify(config, null, 2), { encoding: 'utf8', mode: 0o600 });
  fs.renameSync(tempFile, configFile);
}

export function patchConfig(partial: Partial<DaemonConfig>): DaemonConfig {
  const current = loadConfig();
  if (partial.workerIdleTimeoutMs !== undefined) {
    const ms = Number(partial.workerIdleTimeoutMs);
    if (isNaN(ms) || ms < 0 || ms > 86400000) {
      throw new Error(`Invalid workerIdleTimeoutMs: ${partial.workerIdleTimeoutMs}. Must be between 0 and 86400000 ms.`);
    }
    current.workerIdleTimeoutMs = ms;
  }
  if (partial.remote !== undefined) {
    current.remote = {
      ...current.remote,
      ...validateRemotePatch(partial.remote)
    };
  }
  saveConfig(current);
  return current;
}
