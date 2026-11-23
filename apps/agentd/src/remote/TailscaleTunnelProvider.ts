import * as child_process from 'node:child_process';
import * as fs from 'node:fs';
import { BaseTunnelProvider, type TunnelStartResult } from './TunnelProvider.js';

export interface TailscaleStatusInfo {
  installed: boolean;
  running: boolean;
  hostname?: string;
  domain?: string;
  magicDnsSuffix?: string;
}

export class TailscaleTunnelProvider extends BaseTunnelProvider {
  public readonly name = 'tailscale';

  public static findBinary(): string | null {
    const isWin = process.platform === 'win32';
    const standardPaths = isWin
      ? ['C:\\Program Files\\Tailscale\\tailscale.exe', 'C:\\Program Files (x86)\\Tailscale\\tailscale.exe']
      : ['/Applications/Tailscale.app/Contents/MacOS/Tailscale', '/usr/local/bin/tailscale', '/usr/bin/tailscale'];

    for (const p of standardPaths) {
      if (fs.existsSync(p)) return p;
    }

    try {
      const checkCmd = isWin ? 'where.exe' : 'which';
      const out = child_process.execFileSync(checkCmd, ['tailscale'], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
        windowsHide: true
      });
      const firstLine = out.trim().split(/\r?\n/)[0];
      if (firstLine && fs.existsSync(firstLine)) return firstLine;
    } catch {}

    return null;
  }

  public static getTailscaleInfo(): TailscaleStatusInfo {
    const bin = TailscaleTunnelProvider.findBinary();
    if (!bin) return { installed: false, running: false };

    try {
      const out = child_process.execFileSync(bin, ['status', '--json'], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
        timeout: 4000,
        windowsHide: true
      });
      const parsed = JSON.parse(out);
      const running = parsed.BackendState === 'Running';
      const hostname = parsed.Self?.HostName;
      let domain = parsed.CertDomains?.[0] || parsed.Self?.DNSName;
      if (domain && domain.endsWith('.')) domain = domain.slice(0, -1);
      const magicDnsSuffix = parsed.MagicDNSSuffix;

      return {
        installed: true,
        running,
        hostname: hostname || undefined,
        domain: domain || undefined,
        magicDnsSuffix: magicDnsSuffix || undefined
      };
    } catch {
      return { installed: true, running: false };
    }
  }

  public static setHostname(newHostname: string): { ok: boolean; domain?: string } {
    const bin = TailscaleTunnelProvider.findBinary();
    if (!bin) throw new Error('Tailscale is not installed on this computer.');

    const clean = newHostname
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9-]/g, '');
    if (!clean || clean.length < 2 || clean.length > 32) {
      throw new Error('The host name must have 2 to 32 alphanumeric characters (lower-case letters, digits, hyphens).');
    }

    try {
      child_process.execFileSync(bin, ['set', `--hostname=${clean}`], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
        timeout: 5000,
        windowsHide: true
      });
    } catch (err: any) {
      throw new Error(`Error updating the Tailscale host name: ${err.message}`);
    }

    const info = TailscaleTunnelProvider.getTailscaleInfo();
    return { ok: true, domain: info.domain };
  }

  public static async install(): Promise<{ ok: boolean; message: string }> {
    if (process.platform === 'win32') {
      return new Promise((resolve, reject) => {
        child_process.execFile(
          'winget',
          ['install', '--id', 'Tailscale.Tailscale', '-e', '--accept-package-agreements', '--accept-source-agreements'],
          { windowsHide: true },
          (err) => {
            if (err) return reject(new Error(`Error installing Tailscale with winget: ${err.message}`));
            resolve({ ok: true, message: 'Tailscale installation started.' });
          }
        );
      });
    }
    throw new Error(
      'Automatic install is supported on Windows with winget. On macOS, get it from the Mac App Store or with brew.'
    );
  }

  protected async doStart(localPort: number): Promise<TunnelStartResult> {
    this.setState('starting', { error: null, url: null });

    const bin = TailscaleTunnelProvider.findBinary();
    if (!bin) {
      const msg = 'Tailscale is not installed. Install it to use the private permanent Tailscale tunnel.';
      this.setState('error', { error: msg });
      throw new Error(msg);
    }

    const info = TailscaleTunnelProvider.getTailscaleInfo();
    if (!info.running) {
      const msg = 'Tailscale is not connected. Open the Tailscale app and sign in to turn on the network.';
      this.setState('error', { error: msg });
      throw new Error(msg);
    }

    if (!info.domain) {
      const msg =
        'Could not determine the Tailscale domain of this machine. Check that MagicDNS is on in the Tailscale dashboard.';
      this.setState('error', { error: msg });
      throw new Error(msg);
    }

    try {
      child_process.execFileSync(bin, ['serve', '--bg', '--https=443', `127.0.0.1:${localPort}`], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
        timeout: 6000,
        windowsHide: true
      });
    } catch (err: any) {
      const msg = `Error starting tailscale serve: ${err.message}`;
      this.setState('error', { error: msg });
      throw new Error(msg);
    }

    const url = `https://${info.domain}`;
    this.setState('running', { url, error: null });
    return { url, provider: this.name };
  }

  public async stop(): Promise<void> {
    const bin = TailscaleTunnelProvider.findBinary();
    if (bin) {
      try {
        child_process.execFileSync(bin, ['serve', '--https=443', 'off'], {
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'ignore'],
          timeout: 4000,
          windowsHide: true
        });
      } catch {}
    }
    this.setState('stopped', { url: null, error: null });
  }
}
