import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';
import { ulid } from 'ulid';
import { getPiFrameBaseDir } from '../config/config.js';
import { timingSafeEqualStrings } from '../server/auth.js';
import type {
  PairedDevice,
  PublicPairedDevice,
  PairingSecret,
  RemoteDeviceMode
} from './types.js';

/** Sliding lifetime of a device credential: renewed on every authenticated use. */
export const DEVICE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
export const MAX_PAIRED_DEVICES = 10;
export const DEFAULT_PAIRING_TTL_MS = 5 * 60 * 1000;
/** After this many failed attempts (from anyone) the active pairing secret is destroyed. */
export const MAX_PAIRING_FAILURES = 5;

const IP_MAX_FAILURES = 5;
const IP_LOCKOUT_MS = 15 * 60 * 1000;
const IP_WINDOW_MS = 15 * 60 * 1000;
const IP_MAP_MAX_ENTRIES = 5000;
const SAVE_DEBOUNCE_MS = 30_000;
const TOKEN_PREFIX = 'rem_dev_';

interface IpRateLimit {
  failedCount: number;
  lockedUntil: number;
  lastAttempt: number;
}

interface ActivePairing extends PairingSecret {
  failures: number;
}

function authError(message: string, code: string): Error {
  return Object.assign(new Error(message), { code });
}

function sha256Hex(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function safeHashEqual(aHex: string, bHex: string): boolean {
  const a = Buffer.from(aHex, 'hex');
  const b = Buffer.from(bHex, 'hex');
  if (a.length !== b.length || a.length === 0) return false;
  return crypto.timingSafeEqual(a, b);
}

function sanitizeText(value: string, max: number): string {
  // eslint-disable-next-line no-control-regex
  return value.replace(/[\u0000-\u001f\u007f]/g, '').slice(0, max);
}

const DUMMY_HASH = sha256Hex('piframe-dummy-device-secret');

export class RemoteAuthManager {
  private devicesFile: string;
  private devices = new Map<string, PairedDevice>();
  private currentPairing: ActivePairing | null = null;
  private ipRateLimits = new Map<string, IpRateLimit>();
  private saveTimer?: NodeJS.Timeout;
  private dirty = false;
  private now: () => number;

  constructor(customDevicesFile?: string, clock?: () => number) {
    this.devicesFile = customDevicesFile || path.join(getPiFrameBaseDir(), 'remote_devices.json');
    this.now = clock ?? Date.now;
    this.loadDevices();
  }

  // ---------------------------------------------------------------------------
  // Persistence (hashes only, owner-only file)
  // ---------------------------------------------------------------------------

  private loadDevices(): void {
    if (!fs.existsSync(this.devicesFile)) return;
    try {
      const parsed = JSON.parse(fs.readFileSync(this.devicesFile, 'utf8'));
      const list: unknown[] = Array.isArray(parsed?.devices) ? parsed.devices : [];
      const now = this.now();
      for (const raw of list) {
        const dev = raw as Partial<PairedDevice>;
        // Legacy (plaintext token) or malformed records are discarded: fail closed.
        if (!dev || typeof dev.deviceId !== 'string' || typeof dev.tokenHash !== 'string') continue;
        if (!/^[a-f0-9]{64}$/.test(dev.tokenHash)) continue;
        const expiresAt = typeof dev.expiresAt === 'number' ? dev.expiresAt : 0;
        if (expiresAt <= now) continue;
        this.devices.set(dev.deviceId, {
          deviceId: dev.deviceId,
          tokenHash: dev.tokenHash,
          name: sanitizeText(String(dev.name ?? 'Web Client'), 60),
          userAgent: dev.userAgent ? sanitizeText(String(dev.userAgent), 200) : undefined,
          mode: dev.mode === 'control' ? 'control' : 'view',
          createdAt: Number(dev.createdAt) || now,
          lastUsedAt: Number(dev.lastUsedAt) || now,
          expiresAt,
          remoteIp: dev.remoteIp ? sanitizeText(String(dev.remoteIp), 64) : undefined
        });
      }
    } catch (err) {
      console.error('[RemoteAuth] Failed to load remote devices:', err);
    }
  }

  private saveDevices(): void {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
      this.saveTimer = undefined;
    }
    this.dirty = false;
    try {
      fs.mkdirSync(path.dirname(this.devicesFile), { recursive: true });
      const tempFile = `${this.devicesFile}.tmp.${process.pid}.${crypto.randomBytes(4).toString('hex')}`;
      const payload = JSON.stringify({ version: 2, devices: Array.from(this.devices.values()) }, null, 2);
      fs.writeFileSync(tempFile, payload, { encoding: 'utf8', mode: 0o600 });
      try {
        fs.chmodSync(tempFile, 0o600);
      } catch {
        // chmod is a no-op on Windows; the file lives in the per-user profile directory.
      }
      fs.renameSync(tempFile, this.devicesFile);
    } catch (err) {
      console.error('[RemoteAuth] Failed to save remote devices:', err);
    }
  }

  private scheduleSave(): void {
    this.dirty = true;
    if (this.saveTimer) return;
    this.saveTimer = setTimeout(() => {
      this.saveTimer = undefined;
      if (this.dirty) this.saveDevices();
    }, SAVE_DEBOUNCE_MS);
    this.saveTimer.unref?.();
  }

  /** Persists pending (debounced) changes such as lastUsedAt. */
  public flush(): void {
    if (this.dirty) this.saveDevices();
  }

  // ---------------------------------------------------------------------------
  // Pairing
  // ---------------------------------------------------------------------------

  public generatePairing(ttlMs = DEFAULT_PAIRING_TTL_MS): PairingSecret {
    const ttl = Math.min(Math.max(Number(ttlMs) || DEFAULT_PAIRING_TTL_MS, 30_000), 15 * 60 * 1000);
    // High-entropy 256-bit URL secret. There is intentionally NO short human-typable code.
    const secret = `pair_tok_${crypto.randomBytes(32).toString('base64url')}`;
    this.currentPairing = { secret, expiresAt: this.now() + ttl, failures: 0 };
    return { secret, expiresAt: this.currentPairing.expiresAt };
  }

  public getActivePairing(): PairingSecret | null {
    if (!this.currentPairing) return null;
    if (this.now() > this.currentPairing.expiresAt) {
      this.currentPairing = null;
      return null;
    }
    return { secret: this.currentPairing.secret, expiresAt: this.currentPairing.expiresAt };
  }

  public clearActivePairing(): void {
    this.currentPairing = null;
  }

  private pruneIpLimits(): void {
    const now = this.now();
    for (const [ip, limit] of this.ipRateLimits) {
      if (limit.lockedUntil <= now && now - limit.lastAttempt > IP_WINDOW_MS) this.ipRateLimits.delete(ip);
    }
    while (this.ipRateLimits.size > IP_MAP_MAX_ENTRIES) {
      const oldest = this.ipRateLimits.keys().next().value;
      if (oldest === undefined) break;
      this.ipRateLimits.delete(oldest);
    }
  }

  private checkIpRateLimit(ip: string): void {
    const now = this.now();
    const limit = this.ipRateLimits.get(ip);
    if (!limit) return;
    if (limit.lockedUntil > now) {
      const remainingSecs = Math.ceil((limit.lockedUntil - now) / 1000);
      throw authError(`Too many failed pairing attempts. Locked for ${remainingSecs}s.`, 'RATE_LIMITED');
    }
    if (now - limit.lastAttempt > IP_WINDOW_MS) this.ipRateLimits.delete(ip);
  }

  private recordFailedAttempt(ip: string): void {
    const now = this.now();
    const limit = this.ipRateLimits.get(ip) || { failedCount: 0, lockedUntil: 0, lastAttempt: now };
    limit.failedCount += 1;
    limit.lastAttempt = now;
    if (limit.failedCount >= IP_MAX_FAILURES) limit.lockedUntil = now + IP_LOCKOUT_MS;
    // re-insert to keep Map insertion order == recency order
    this.ipRateLimits.delete(ip);
    this.ipRateLimits.set(ip, limit);
    if (this.ipRateLimits.size > IP_MAP_MAX_ENTRIES) this.pruneIpLimits();
  }

  public pair(
    candidate: string,
    userAgent?: string,
    ip = 'unknown',
    mode: RemoteDeviceMode = 'view'
  ): { deviceId: string; deviceToken: string; device: PublicPairedDevice } {
    this.checkIpRateLimit(ip);

    const pairing = this.getActivePairing();
    if (!pairing || !this.currentPairing) {
      this.recordFailedAttempt(ip);
      throw authError('Pairing session expired or not initiated', 'PAIRING_EXPIRED');
    }

    const cleanCandidate = typeof candidate === 'string' ? candidate.trim().slice(0, 256) : '';
    const matches = cleanCandidate.length > 0 && timingSafeEqualStrings(cleanCandidate, pairing.secret);

    if (!matches) {
      this.recordFailedAttempt(ip);
      // Global cap: anyone guessing burns the pairing for everybody (desktop must regenerate it).
      this.currentPairing.failures += 1;
      if (this.currentPairing.failures >= MAX_PAIRING_FAILURES) this.currentPairing = null;
      throw authError('Invalid pairing secret', 'PAIRING_INVALID');
    }

    this.pruneExpiredDevices();
    if (this.devices.size >= MAX_PAIRED_DEVICES) {
      throw authError(`Maximum number of paired devices reached (${MAX_PAIRED_DEVICES}).`, 'REMOTE_DEVICE_LIMIT');
    }

    // Single-use: the secret is destroyed on first successful use.
    this.currentPairing = null;
    this.ipRateLimits.delete(ip);

    const now = this.now();
    const deviceId = `dev_${ulid()}`;
    const deviceSecret = crypto.randomBytes(32).toString('base64url');
    const deviceToken = `rem_${deviceId}.${deviceSecret}`;

    const ua = userAgent ? sanitizeText(userAgent, 200) : undefined;
    let name = 'Web Client';
    if (ua) {
      if (/iPhone|iPad|iPod/.test(ua)) name = 'Apple iOS Device';
      else if (/Android/.test(ua)) name = 'Android Device';
      else if (/Macintosh/.test(ua)) name = 'macOS Browser';
      else if (/Windows/.test(ua)) name = 'Windows Browser';
      else if (/Linux/.test(ua)) name = 'Linux Browser';
    }

    const device: PairedDevice = {
      deviceId,
      tokenHash: sha256Hex(deviceSecret),
      name,
      userAgent: ua,
      mode: mode === 'control' ? 'control' : 'view',
      createdAt: now,
      lastUsedAt: now,
      expiresAt: now + DEVICE_TTL_MS,
      remoteIp: ip !== 'unknown' ? sanitizeText(ip, 64) : undefined
    };
    this.devices.set(deviceId, device);
    this.saveDevices();

    return { deviceId, deviceToken, device: this.toPublic(device) };
  }

  // ---------------------------------------------------------------------------
  // Device credentials
  // ---------------------------------------------------------------------------

  private pruneExpiredDevices(): void {
    const now = this.now();
    let removed = false;
    for (const [id, dev] of this.devices) {
      if (dev.expiresAt <= now) {
        this.devices.delete(id);
        removed = true;
      }
    }
    if (removed) this.saveDevices();
  }

  /** Verifies a device token; on success renews its sliding expiry. */
  public verifyDeviceToken(token: string): PairedDevice | null {
    if (typeof token !== 'string' || token.length > 300 || !token.startsWith(TOKEN_PREFIX)) return null;
    const dot = token.indexOf('.');
    if (dot < 0) return null;
    const deviceId = token.slice('rem_'.length, dot);
    const secret = token.slice(dot + 1);
    if (!deviceId || !secret) return null;

    const dev = this.devices.get(deviceId);
    // Always perform one hash comparison so unknown ids and wrong secrets take similar time.
    const ok = safeHashEqual(sha256Hex(secret), dev ? dev.tokenHash : DUMMY_HASH);
    if (!dev || !ok) return null;

    const now = this.now();
    if (dev.expiresAt <= now) {
      this.devices.delete(deviceId);
      this.saveDevices();
      return null;
    }
    dev.lastUsedAt = now;
    dev.expiresAt = now + DEVICE_TTL_MS;
    this.scheduleSave();
    return dev;
  }

  /** Returns the device only if it still exists and has not expired (no renewal). */
  public getDevice(deviceId: string | undefined): PairedDevice | null {
    if (!deviceId) return null;
    const dev = this.devices.get(deviceId);
    if (!dev) return null;
    if (dev.expiresAt <= this.now()) {
      this.devices.delete(deviceId);
      this.saveDevices();
      return null;
    }
    return dev;
  }

  public setDeviceMode(deviceId: string, mode: RemoteDeviceMode): boolean {
    const dev = this.devices.get(deviceId);
    if (!dev) return false;
    dev.mode = mode === 'control' ? 'control' : 'view';
    this.saveDevices();
    return true;
  }

  public revokeDevice(deviceId: string): boolean {
    const existed = this.devices.delete(deviceId);
    if (existed) this.saveDevices();
    return existed;
  }

  public revokeAll(): void {
    this.devices.clear();
    this.saveDevices();
  }

  private toPublic(dev: PairedDevice): PublicPairedDevice {
    return {
      deviceId: dev.deviceId,
      name: dev.name,
      userAgent: dev.userAgent,
      mode: dev.mode,
      createdAt: dev.createdAt,
      lastUsedAt: dev.lastUsedAt,
      expiresAt: dev.expiresAt,
      remoteIp: dev.remoteIp
    };
  }

  public getPairedDevices(): PublicPairedDevice[] {
    this.pruneExpiredDevices();
    return Array.from(this.devices.values()).map((dev) => this.toPublic(dev));
  }
}
