export type RemoteDeviceMode = 'view' | 'control';

/** Persisted device record. The device secret itself is NEVER stored: only its SHA-256 hash. */
export interface PairedDevice {
  deviceId: string;
  tokenHash: string;
  name: string;
  userAgent?: string;
  mode: RemoteDeviceMode;
  createdAt: number;
  lastUsedAt: number;
  expiresAt: number;
  remoteIp?: string;
}

export interface PublicPairedDevice {
  deviceId: string;
  name: string;
  userAgent?: string;
  mode: RemoteDeviceMode;
  createdAt: number;
  lastUsedAt: number;
  expiresAt: number;
  remoteIp?: string;
}

export interface PairingSecret {
  secret: string;
  expiresAt: number;
}

export interface TailscaleStatusInfo {
  installed: boolean;
  running: boolean;
  hostname?: string;
  domain?: string;
  magicDnsSuffix?: string;
}

export interface RemoteStatus {
  enabled: boolean;
  state: 'stopped' | 'starting' | 'running' | 'error';
  url?: string;
  tunnelProvider: string;
  cloudflaredInstalled: boolean;
  cloudflaredPath?: string;
  tailscale?: TailscaleStatusInfo;
  error?: string;
  localPort?: number;
  devices: PublicPairedDevice[];
  pairingPending?: {
    expiresAt: number;
    url?: string;
  };
  options: {
    defaultMode: RemoteDeviceMode;
  };
}
