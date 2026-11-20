import * as fs from 'node:fs/promises';
import * as os from 'node:os';
import * as path from 'node:path';
import { execFile, type ExecFileOptionsWithStringEncoding } from 'node:child_process';
import { promisify } from 'node:util';
import { gt, lt, rsort, valid } from 'semver';
import { resolveNpmLaunch, resolvePiLaunch, type PiLaunchCommand } from './executable.js';
import { getAugmentedEnv } from './env.js';

const execFileAsync = promisify(execFile);
const PACKAGE_VERSION = /^(?:v)?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

export interface PiPackageInfo {
  source: string;
  name: string;
  version: string | null;
  pinnedVersion: string | null;
  latestVersion?: string;
  updateError?: string;
}

export interface PiPackageUpdateResult {
  output: string;
  status: 'updated' | 'current' | 'pinned';
  previousVersion: string | null;
  version: string | null;
}

export interface PiPackageOperations {
  list(checkUpdates?: boolean): Promise<PiPackageInfo[]>;
  update(source: string): Promise<PiPackageUpdateResult>;
  remove(source: string): Promise<{ output: string }>;
  pin(source: string, version: string): Promise<{ output: string; source: string }>;
}

type PackageCommandRunner = (
  file: string,
  args: string[],
  options: ExecFileOptionsWithStringEncoding,
) => Promise<{ stdout: string; stderr: string }>;

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
  private readonly installPaths = new Map<string, string>();
  private readonly updateChecks = new Map<string, {
    version: string;
    latestVersion: string;
    updateError?: string;
  }>();

  constructor(
    private readonly piExecutablePath: string,
    private readonly runCommand: PackageCommandRunner = execFileAsync,
  ) {}

  private async execute(launch: PiLaunchCommand, timeout = 120_000): Promise<string> {
    try {
      const { stdout } = await this.runCommand(launch.file, launch.args, {
        cwd: os.homedir(),
        timeout,
        maxBuffer: 2 * 1024 * 1024,
        windowsHide: true,
        encoding: 'utf8',
        env: getAugmentedEnv({ npm_config_prefer_online: 'true' }),
      });
      return stdout.trim();
    } catch (cause) {
      const error = cause instanceof Error ? cause.message : String(cause);
      throw new Error(`Pi package command failed: ${error}`, { cause });
    }
  }

  private async run(args: string[]): Promise<string> {
    if (!this.piExecutablePath) throw new Error('Pi executable is not configured.');
    return this.execute(resolvePiLaunch(this.piExecutablePath, args));
  }

  private async latestNpmVersion(source: string): Promise<string> {
    const base = npmBaseSource(source);
    if (!base) throw new Error(`Not an npm package: ${source}`);
    const spec = base === source ? `${source.slice(4)}@latest` : source.slice(4);
    const output = await this.execute(
      resolveNpmLaunch(this.piExecutablePath, ['view', spec, 'version', '--json']),
      30_000,
    );
    const decoded: unknown = JSON.parse(output);
    const versions = typeof decoded === 'string' ? [decoded] : decoded;
    if (!Array.isArray(versions) || versions.length === 0 ||
        !versions.every((version): version is string => typeof version === 'string' && valid(version) !== null)) {
      throw new Error(`npm returned no valid version for ${source}.`);
    }
    return rsort(versions)[0];
  }

  private async checkNpmCompatibility(source: string, target: string): Promise<string | undefined> {
    const base = npmBaseSource(source);
    if (!base) throw new Error(`Not an npm package: ${source}`);
    const installPath = this.installPaths.get(source);
    const index = installPath?.lastIndexOf(`${path.sep}node_modules${path.sep}`) ?? -1;
    if (!installPath || index < 0) {
      throw new Error(`Cannot locate the managed npm installation of ${source}.`);
    }
    const spec = `${base.slice(4)}@${target}`;
    try {
      await this.execute(resolveNpmLaunch(this.piExecutablePath, [
        'install', spec, '--prefix', installPath.slice(0, index),
        '--dry-run', '--ignore-scripts', '--package-lock=false',
        '--legacy-peer-deps', '--no-audit', '--no-fund', '--json',
      ]), 30_000);
      return undefined;
    } catch (error) {
      const cause = error instanceof Error ? error.cause : undefined;
      if (typeof cause !== 'object' || cause === null || !('stdout' in cause) ||
          typeof cause.stdout !== 'string' || !cause.stdout.trim().startsWith('{')) {
        throw error;
      }
      let response: unknown;
      try {
        response = JSON.parse(cause.stdout);
      } catch (parseError) {
        if (parseError instanceof SyntaxError) throw error;
        throw parseError;
      }
      if (typeof response !== 'object' || response === null || !('error' in response) ||
          typeof response.error !== 'object' || response.error === null ||
          !('code' in response.error) || response.error.code !== 'EBADPLATFORM') {
        throw error;
      }
      const details = 'summary' in response.error && typeof response.error.summary === 'string'
        ? response.error.summary : 'Unsupported package platform.';
      return `${source}: version ${target} is not installable on ${process.platform}/${process.arch}: ${details}`;
    }
  }

  async list(checkUpdates = false): Promise<PiPackageInfo[]> {
    const listed = parsePiListOutput(await this.run(['list']));
    return Promise.all(listed.map(async ({ source, installPath }) => {
      let name = source;
      let version: string | null = null;
      if (installPath) {
        this.installPaths.set(source, installPath);
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
      const pinnedVersion = pinnedNpmVersion(source);
      const info: PiPackageInfo = { source, name, version, pinnedVersion };
      const previousCheck = this.updateChecks.get(source);
      if (previousCheck?.version === version) {
        info.latestVersion = previousCheck.latestVersion;
        info.updateError = previousCheck.updateError;
      }
      if (checkUpdates && npmBaseSource(source) && !pinnedVersion) {
        if (!version || !valid(version)) {
          throw new Error(`Cannot read the installed version of ${source}.`);
        }
        info.latestVersion = await this.latestNpmVersion(source);
        info.updateError = gt(info.latestVersion, version)
          ? await this.checkNpmCompatibility(source, info.latestVersion) : undefined;
        this.updateChecks.set(source, {
          version, latestVersion: info.latestVersion, updateError: info.updateError,
        });
      }
      return info;
    }));
  }

  private async requireInstalled(source: string): Promise<PiPackageInfo> {
    const installed = (await this.list()).find((item) => item.source === source);
    if (!installed) {
      throw new Error(`Pi package is not installed in user scope: ${source}`);
    }
    return installed;
  }

  async update(source: string): Promise<PiPackageUpdateResult> {
    const before = await this.requireInstalled(source);
    if (before.pinnedVersion) {
      return { output: '', status: 'pinned', previousVersion: before.version, version: before.version };
    }
    const target = npmBaseSource(source) ? await this.latestNpmVersion(source) : null;
    if (target && before.version && valid(before.version) && !gt(target, before.version)) {
      return { output: '', status: 'current', previousVersion: before.version, version: before.version };
    }
    if (target) {
      const compatibilityError = await this.checkNpmCompatibility(source, target);
      if (compatibilityError) {
        throw Object.assign(new Error(compatibilityError), { code: 'PACKAGE_UPDATE_UNSUPPORTED_PLATFORM' });
      }
    }
    const output = await this.run(['update', source]);
    const after = await this.requireInstalled(source);
    if (target && (!after.version || !valid(after.version) || lt(after.version, target))) {
      throw new Error(
        `${source}: installed version ${after.version ?? 'unknown'}, expected ${target}. ` +
        `The update did not install the available version.${output ? `\n${output}` : ''}`,
      );
    }
    return { output, status: 'updated', previousVersion: before.version, version: after.version };
  }

  async remove(source: string): Promise<{ output: string }> {
    await this.requireInstalled(source);
    return { output: await this.run(['remove', source]) };
  }

  async pin(source: string, version: string): Promise<{ output: string; source: string }> {
    await this.requireInstalled(source);
    const pinnedSource = pinnedNpmSource(source, version);
    const output = await this.run(['install', pinnedSource]);
    const installed = await this.requireInstalled(pinnedSource);
    if (installed.version?.replace(/^v/, '') !== version.trim().replace(/^v/, '')) {
      throw new Error(`${pinnedSource}: installed version ${installed.version ?? 'unknown'} does not match the pinned version.`);
    }
    return { output, source: pinnedSource };
  }
}
