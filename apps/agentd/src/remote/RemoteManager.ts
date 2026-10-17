import type * as http from 'node:http';
import * as net from 'node:net';
import { EventEmitter } from 'node:events';
import {
  loadConfig,
  patchConfig,
  validateRemotePatch,
  type DaemonConfig
} from '../config/config.js';
import { RemoteAuthManager } from './RemoteAuthManager.js';
import { CloudflaredTunnelProvider } from './CloudflaredTunnelProvider.js';
import { CustomTunnelProvider } from './CustomTunnelProvider.js';
import { TailscaleTunnelProvider } from './TailscaleTunnelProvider.js';
import type { TunnelProvider } from './TunnelProvider.js';
import type {
  RemoteStatus,
  PublicPairedDevice,
  PairingSecret,
  RemoteDeviceMode
} from './types.js';

export interface RemoteManagerEvents {
  statusChanged: (status: RemoteStatus) => void;
  deviceRevoked: (deviceId: string) => void;
  allDevicesRevoked: () => void;
  deviceModeChanged: (payload: { deviceId: string; mode: RemoteDeviceMode }) => void;
  tunnelDown: () => void;
  stopped: () => void;
}

export class RemoteManager extends EventEmitter {
  private config: DaemonConfig;
  private authManager: RemoteAuthManager;
  private tunnelProvider: TunnelProvider;
  private listenerPort = 0;
  private expectedHost?: string;
  private startPromise?: Promise<RemoteStatus>;
  private boundProviderChangeListener: () => void;

  constructor(config?: DaemonConfig, authManager?: RemoteAuthManager) {
    super();
    this.config = config || loadConfig();
    this.authManager = authManager || new RemoteAuthManager();
    this.boundProviderChangeListener = () => this.onProviderChange();
    this.tunnelProvider = this.createProvider(this.config.remote.tunnelProvider);
  }

  public setListenerPort(port: number): void {
    this.listenerPort = port;
  }

  public getListenerPort(): number {
    return this.listenerPort;
  }

  public getAuthManager(): RemoteAuthManager {
    return this.authManager;
  }

  public flush(): void {
    this.authManager.flush();
  }

  private createProvider(providerName: 'cloudflared' | 'tailscale' | 'custom'): TunnelProvider {
    if (this.tunnelProvider) {
      this.tunnelProvider.removeAllListeners('change');
    }
    let provider: TunnelProvider;
    if (providerName === 'tailscale') {
      provider = new TailscaleTunnelProvider();
    } else if (providerName === 'custom') {
      provider = new CustomTunnelProvider({
        url: this.config.remote.customTunnelUrl,
        command: this.config.remote.customTunnelCommand
      });
    } else {
      provider = new CloudflaredTunnelProvider();
    }
    provider.on('change', this.boundProviderChangeListener);
    return provider;
  }

  private onProviderChange(): void {
    if (this.tunnelProvider.getState() !== 'running') {
      this.expectedHost = undefined;
      this.authManager.clearActivePairing();
      this.emit('tunnelDown');
    }
    this.emitStatus();
  }

  public async start(
    options?: {
      tunnelProvider?: 'cloudflared' | 'custom';
      customCommand?: string;
      customUrl?: string;
    },
    behavior?: { generatePairing?: boolean }
  ): Promise<RemoteStatus> {
    if (this.startPromise) return this.startPromise;

    this.startPromise = (async () => {
      if (!this.listenerPort) {
        throw Object.assign(new Error('Remote listener port not initialized'), {
          code: 'LISTENER_NOT_INITIALIZED'
        });
      }

      // Validate options strictly before applying any changes
      let patchToApply: ReturnType<typeof validateRemotePatch> = {};
      if (options) {
        patchToApply = validateRemotePatch({
          ...(options.tunnelProvider ? { tunnelProvider: options.tunnelProvider } : {}),
          ...(options.customCommand !== undefined ? { customTunnelCommand: options.customCommand } : {}),
          ...(options.customUrl !== undefined ? { customTunnelUrl: options.customUrl } : {})
        });
      }

      // Recreate provider if needed
      const targetProvider = patchToApply.tunnelProvider || this.config.remote.tunnelProvider;
      if (targetProvider !== this.tunnelProvider.name || options?.customCommand !== undefined || options?.customUrl !== undefined) {
        this.config = {
          ...this.config,
          remote: {
            ...this.config.remote,
            ...patchToApply
          }
        };
        this.tunnelProvider = this.createProvider(targetProvider);
      }

      this.emitStatus();

      try {
        const res = await this.tunnelProvider.start(this.listenerPort);
        const parsed = new URL(res.url);
        this.expectedHost = parsed.host.toLowerCase();

        // Persist enabled: true ONLY after successful start
        this.config = patchConfig({
          remote: {
            ...this.config.remote,
            ...patchToApply,
            enabled: true
          }
        });

        if (behavior?.generatePairing !== false) {
          // 5-minute pairing code ready for initial connection
          this.authManager.generatePairing(5 * 60 * 1000);
        }

        this.emitStatus();
        return this.getStatus();
      } catch (err) {
        this.expectedHost = undefined;
        this.emitStatus();
        throw err;
      }
    })().finally(() => {
      this.startPromise = undefined;
    });

    return this.startPromise;
  }

  public async stop(options?: { persistEnabled?: boolean }): Promise<RemoteStatus> {
    if (options?.persistEnabled !== false) {
      this.config = patchConfig({
        remote: {
          ...this.config.remote,
          enabled: false
        }
      });
    }

    await this.tunnelProvider.stop();
    this.expectedHost = undefined;
    this.authManager.clearActivePairing();
    this.emit('stopped');
    this.emitStatus();
    return this.getStatus();
  }

  public generatePairing(ttlMs = 5 * 60 * 1000): PairingSecret & { url?: string } {
    if (!this.config.remote.enabled || this.tunnelProvider.getState() !== 'running') {
      throw Object.assign(new Error('Remote access is not running'), {
        code: 'REMOTE_NOT_ACTIVE'
      });
    }

    const pairing = this.authManager.generatePairing(ttlMs);
    const tunnelUrl = this.tunnelProvider.getUrl();
    // Use URL fragment (#pair=) so secrets are never sent in HTTP query parameters or proxy logs
    const pairingUrl = tunnelUrl ? `${tunnelUrl}/#pair=${pairing.secret}` : undefined;

    this.emitStatus();
    return {
      ...pairing,
      url: pairingUrl
    };
  }

  public pair(
    candidate: string,
    userAgent?: string,
    ip = 'unknown'
  ): { deviceId: string; deviceToken: string; device: PublicPairedDevice } {
    if (!this.config.remote.enabled || this.tunnelProvider.getState() !== 'running') {
      throw Object.assign(new Error('Remote access is not running'), {
        code: 'REMOTE_NOT_ACTIVE'
      });
    }

    try {
      return this.authManager.pair(
        candidate,
        userAgent,
        ip,
        this.config.remote.defaultMode
      );
    } finally {
      this.emitStatus();
    }
  }

  public setDeviceMode(deviceId: string, mode: RemoteDeviceMode): boolean {
    const ok = this.authManager.setDeviceMode(deviceId, mode);
    if (ok) {
      this.emit('deviceModeChanged', { deviceId, mode });
      this.emitStatus();
    }
    return ok;
  }

  public revokeDevice(deviceId: string): boolean {
    const removed = this.authManager.revokeDevice(deviceId);
    if (removed) {
      this.emit('deviceRevoked', deviceId);
      this.emitStatus();
    }
    return removed;
  }

  public revokeAll(): void {
    this.authManager.revokeAll();
    this.emit('allDevicesRevoked');
    this.emitStatus();
  }

  public setOptions(opts: { defaultMode?: RemoteDeviceMode }): RemoteStatus {
    const patch = validateRemotePatch(opts);
    this.config = patchConfig({
      remote: {
        ...this.config.remote,
        ...patch
      }
    });
    this.emitStatus();
    return this.getStatus();
  }

  public async installTailscale(): Promise<{ ok: boolean; message: string }> {
    const res = await TailscaleTunnelProvider.install();
    this.emitStatus();
    return res;
  }

  public setTailscaleHostname(name: string): { ok: boolean; domain?: string } {
    const res = TailscaleTunnelProvider.setHostname(name);
    this.emitStatus();
    return res;
  }

  public async installCloudflared(): Promise<{ ok: boolean; path: string }> {
    const installedPath = await CloudflaredTunnelProvider.downloadAndInstall();
    this.emitStatus();
    return { ok: true, path: installedPath };
  }

  public getStatus(): RemoteStatus {
    const url = this.tunnelProvider.getUrl();
    const pairing = this.authManager.getActivePairing();
    const pairingPending = pairing
      ? {
          expiresAt: pairing.expiresAt,
          url: url ? `${url}/#pair=${pairing.secret}` : undefined
        }
      : undefined;

    const cloudflaredPath = CloudflaredTunnelProvider.findBinary();
    const tailscaleInfo = TailscaleTunnelProvider.getTailscaleInfo();

    return {
      enabled: this.config.remote.enabled,
      state: this.tunnelProvider.getState(),
      url,
      tunnelProvider: this.tunnelProvider.name,
      cloudflaredInstalled: Boolean(cloudflaredPath),
      cloudflaredPath: cloudflaredPath ?? undefined,
      tailscale: tailscaleInfo,
      error: this.tunnelProvider.getError(),
      localPort: this.listenerPort || undefined,
      devices: this.authManager.getPairedDevices(),
      pairingPending,
      options: {
        defaultMode: this.config.remote.defaultMode
      }
    };
  }

  private emitStatus(): void {
    this.emit('statusChanged', this.getStatus());
  }

  public getTrustedClientIp(req: http.IncomingMessage): string {
    const socketIp = req.socket.remoteAddress?.replace(/^::ffff:/, '') || 'unknown';
    if (this.config.remote.tunnelProvider === 'cloudflared') {
      const cfIp = req.headers['cf-connecting-ip'];
      if (typeof cfIp === 'string' && net.isIP(cfIp.trim())) {
        return cfIp.trim();
      }
    }
    return socketIp;
  }

  private getTargetExpectedHost(): string | undefined {
    if (this.expectedHost) return this.expectedHost;
    if (this.config.remote.tunnelProvider === 'tailscale') {
      const ts = TailscaleTunnelProvider.getTailscaleInfo();
      if (ts.domain) return ts.domain.toLowerCase();
    } else if (this.config.remote.customTunnelUrl) {
      try {
        return new URL(this.config.remote.customTunnelUrl).host.toLowerCase();
      } catch {}
    }
    return undefined;
  }

  public isRemoteHostAllowed(host: string | undefined): boolean {
    if (!this.config.remote.enabled || this.tunnelProvider.getState() !== 'running' || !host) {
      return false;
    }
    const expected = this.getTargetExpectedHost();
    if (!expected) return false;

    try {
      // Host may contain port (e.g. example.com:443 or tunnel.example.com)
      const parsed = new URL(`https://${host}`);
      if (parsed.username || parsed.password) return false;
      return parsed.host.toLowerCase() === expected;
    } catch {
      return false;
    }
  }

  public isRemoteOriginAllowed(origin: string | undefined): boolean {
    if (!this.config.remote.enabled || this.tunnelProvider.getState() !== 'running' || !origin) {
      return false;
    }
    const expected = this.getTargetExpectedHost();
    if (!expected) return false;

    try {
      const parsed = new URL(origin);
      if (parsed.protocol !== 'https:') return false;
      return parsed.host.toLowerCase() === expected;
    } catch {
      return false;
    }
  }
}
