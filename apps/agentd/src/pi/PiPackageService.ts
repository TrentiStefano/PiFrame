import * as fs from 'node:fs/promises';
import * as os from 'node:os';
import * as path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { resolvePiLaunch } from './executable.js';
import { getAugmentedEnv } from './env.js';

const execFileAsync = promisify(execFile);
const PACKAGE_VERSION = /^(?:v)?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

export interface PiPackageInfo {
  source: string;
  name: string;
  version: string | null;
  pinnedVersion: string | null;
}

export interface PiPackageOperations {
  list(): Promise<PiPackageInfo[]>;
  update(source: string): Promise<{ output: string }>;
  remove(source: string): Promise<{ output: string }>;
  pin(source: string, version: string): Promise<{ output: string; source: string }>;
}

interface ListedPackage {
  source: string;
  installPath?: string;
  scope: 'user' | 'project';
}

export function parsePiListOutput(output: string): ListedPackage[] {
  const packages: ListedPackage[] = [];
  let scope: ListedPackage['scope'] = 'user';
  let pending: ListedPackage | undefined;
  const flush = () => {
    if (pending?.scope === 'user') packages.push(pending);
    pending = undefined;
  };

  for (const line of output.split(/\r?\n/)) {
    const heading = line.trim();
    if (heading === 'User packages:') {
      flush();
      scope = 'user';
      continue;
    }
    if (heading === 'Project packages:') {
      flush();
      scope = 'project';
      continue;
    }
    if (/^  \S/.test(line) && !/^    /.test(line)) {
      flush();
      const source = line.trim();
      if (source) pending = { source, scope };
      continue;
    }
    if (pending && /^    \S/.test(line)) {
      pending.installPath = line.trim();
      flush();
    }
  }
  flush();
  return packages;
}

export function npmBaseSource(source: string): string | null {
  if (!source.startsWith('npm:')) return null;
  const packagePath = source.slice(4);
  const separator = packagePath.lastIndexOf('/');
  const versionSeparator = packagePath.lastIndexOf('@');
  return `npm:${versionSeparator > separator ? packagePath.slice(0, versionSeparator) : packagePath}`;
}

export function pinnedNpmVersion(source: string): string | null {
  const base = npmBaseSource(source);
  if (!base || base === source) return null;
  const version = source.slice(base.length + 1);
  return PACKAGE_VERSION.test(version) ? version.replace(/^v/, '') : null;
}

export function pinnedNpmSource(source: string, version: string): string {
  const base = npmBaseSource(source);
  const normalizedVersion = version.trim().replace(/^v/, '');
  if (!base || !PACKAGE_VERSION.test(normalizedVersion)) {
    throw new Error('Only npm packages can be pinned; enter a full semantic version (for example 1.2.3).');
  }
  return `${base}@${normalizedVersion}`;
}

export class PiPackageService implements PiPackageOperations {
  constructor(private readonly piExecutablePath: string) {}

  private async run(args: string[]): Promise<string> {
    if (!this.piExecutablePath) throw new Error('Pi executable is not configured.');
    const launch = resolvePiLaunch(this.piExecutablePath, args);
    try {
      const { stdout } = await execFileAsync(launch.file, launch.args, {
        cwd: os.homedir(),
        timeout: 120_000,
        maxBuffer: 2 * 1024 * 1024,
        windowsHide: true,
        env: getAugmentedEnv(),
      });
      return stdout.trim();
    } catch (cause) {
      const error = cause instanceof Error ? cause.message : String(cause);
      throw new Error(`Pi package command failed: ${error}`);
    }
  }

  async list(): Promise<PiPackageInfo[]> {
    const listed = parsePiListOutput(await this.run(['list']));
    return Promise.all(listed.map(async ({ source, installPath }) => {
      let name = source;
      let version: string | null = null;
      if (installPath) {
        try {
          const manifest = JSON.parse(
            await fs.readFile(path.join(installPath, 'package.json'), 'utf8'),
          ) as { name?: unknown; version?: unknown };
          if (typeof manifest.name === 'string') name = manifest.name;
          if (typeof manifest.version === 'string') version = manifest.version;
        } catch {
          // Keep the configured source visible if local package metadata is unavailable.
        }
      }
      return { source, name, version, pinnedVersion: pinnedNpmVersion(source) };
    }));
  }

  private async requireInstalled(source: string): Promise<void> {
    if (!(await this.list()).some((item) => item.source === source)) {
      throw new Error(`Pi package is not installed in user scope: ${source}`);
    }
  }

  async update(source: string): Promise<{ output: string }> {
    await this.requireInstalled(source);
    return { output: await this.run(['update', source]) };
  }

  async remove(source: string): Promise<{ output: string }> {
    await this.requireInstalled(source);
    return { output: await this.run(['remove', source]) };
  }

  async pin(source: string, version: string): Promise<{ output: string; source: string }> {
    await this.requireInstalled(source);
    const pinnedSource = pinnedNpmSource(source, version);
    return { output: await this.run(['install', pinnedSource]), source: pinnedSource };
  }
}
