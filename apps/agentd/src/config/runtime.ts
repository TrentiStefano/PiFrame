import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';
import { getPiCrustBaseDir } from './config.js';

export interface RuntimeInfo {
  port: number;
  pid: number;
  version: string;
  startedAt: number;
  protocol: 1;
}

export function getRuntimeDir(): string {
  const dir = path.join(getPiCrustBaseDir(), 'runtime');
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

export function getDaemonJsonPath(): string {
  return path.join(getRuntimeDir(), 'daemon.json');
}

export function getTokenPath(): string {
  return path.join(getRuntimeDir(), 'daemon.token');
}

export function getPidPath(): string {
  return path.join(getRuntimeDir(), 'daemon.pid');
}

export function getLogPath(): string {
  return path.join(getRuntimeDir(), 'daemon.log');
}

export function generateAndSaveToken(): string {
  const token = crypto.randomBytes(32).toString('base64url'); // 256 bits
  const tokenFile = getTokenPath();
  fs.writeFileSync(tokenFile, token, { encoding: 'utf8', mode: 0o600 });
  try {
    fs.chmodSync(tokenFile, 0o600);
  } catch {
    // Windows ACL is applied automatically for user-created file in profile
  }
  return token;
}

export function readToken(): string | null {
  const tokenFile = getTokenPath();
  if (fs.existsSync(tokenFile)) {
    return fs.readFileSync(tokenFile, 'utf8').trim();
  }
  return null;
}

export function writeRuntimeInfo(info: RuntimeInfo): void {
  const file = getDaemonJsonPath();
  fs.writeFileSync(file, JSON.stringify(info, null, 2), 'utf8');
  fs.writeFileSync(getPidPath(), String(info.pid), 'utf8');
}

export function readRuntimeInfo(): RuntimeInfo | null {
  const file = getDaemonJsonPath();
  if (!fs.existsSync(file)) return null;
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

export function cleanupRuntimeFiles(): void {
  const files = [getDaemonJsonPath(), getPidPath(), getTokenPath()];
  for (const f of files) {
    try {
      if (fs.existsSync(f)) {
        fs.unlinkSync(f);
      }
    } catch {
      // Ignore cleanup error on shutdown
    }
  }
}
