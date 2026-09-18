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

export interface DaemonConfig {
  piPath?: string;
  workerIdleTimeoutMs: number;
  journal: JournalConfig;
  log: LogConfig;
  web: WebConfig;
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
  }
};

export function getPiCrustBaseDir(): string {
  if (process.env.PI_CRUST_HOME) {
    return path.resolve(process.env.PI_CRUST_HOME);
  }
  return path.join(os.homedir(), '.pi-crust');
}

export function getConfigFilePath(): string {
  return path.join(getPiCrustBaseDir(), 'config.json');
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
      web: { ...DEFAULT_CONFIG.web, ...(parsed.web || {}) }
    };
  } catch (err) {
    console.error(`Failed to read ${configFile}, using default config:`, err);
    return { ...DEFAULT_CONFIG };
  }
}

export function saveConfig(config: DaemonConfig): void {
  const baseDir = getPiCrustBaseDir();
  fs.mkdirSync(baseDir, { recursive: true });
  const configFile = getConfigFilePath();
  const tempFile = `${configFile}.tmp.${Date.now()}`;

  // Atomic write: write to temp file then rename
  fs.writeFileSync(tempFile, JSON.stringify(config, null, 2), 'utf8');
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
  saveConfig(current);
  return current;
}
