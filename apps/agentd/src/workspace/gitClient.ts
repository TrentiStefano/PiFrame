import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import * as fs from 'node:fs';
import * as path from 'node:path';

const execFileAsync = promisify(execFile);

export type GitFileStatusCode = 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked';

export interface GitFileChange {
  path: string;
  status: GitFileStatusCode;
  staged: boolean;
  unstaged: boolean;
  stagedStatus: string | null;
  unstagedStatus: string | null;
  additions: number;
  deletions: number;
}

export interface GitStatusResult {
  isRepository: boolean;
  rootPath?: string;
  branch?: string;
  files: GitFileChange[];
  totalAdditions: number;
  totalDeletions: number;
}

const EXEC_TIMEOUT_MS = 5000;

export interface WslPathInfo {
  distro: string;
  linuxPath: string;
  uncPrefix: string;
}

export function parseWslPath(cwd: string): WslPathInfo | null {
  if (process.platform !== 'win32') return null;
  const normalized = cwd.trim().replace(/^[\\/]+/, '//').replace(/\\/g, '/').replace(/\/+$/, '');
  const match = normalized.match(/^\/\/(wsl(?:\.localhost|\$))\/([^\/]+)(?:\/(.*))?$/i);
  if (!match) return null;
  const host = match[1];
  const distro = match[2];
  const rest = match[3] || '';
  const linuxPath = ('/' + rest).replace(/\/+/g, '/').replace(/(.)\/$/, '$1');
  const uncPrefix = `\\\\${host}\\${distro}`;
  return { distro, linuxPath, uncPrefix };
}

export function toWslUncPath(linuxPath: string, uncPrefix: string): string {
  const rel = linuxPath.replace(/^\//, '').replace(/\//g, '\\');
  return path.normalize(rel ? `${uncPrefix}\\${rel}` : uncPrefix);
}

async function executeGit(
  args: string[],
  cwd: string,
  acceptedExitCodes: number[] = []
): Promise<string> {
  const wslInfo = parseWslPath(cwd);
  const gitArgs = ['-c', 'safe.directory=*', ...args];
  const run = async (command: string, commandArgs: string[], options: any) => {
    try {
      return (await execFileAsync(command, commandArgs, options)).stdout;
    } catch (error: any) {
      if (acceptedExitCodes.includes(error?.code)) return error.stdout ?? '';
      throw error;
    }
  };

  if (wslInfo) {
    try {
      return await run(
        'wsl.exe',
        ['-d', wslInfo.distro, '--cd', wslInfo.linuxPath, 'git', ...gitArgs],
        {
          timeout: EXEC_TIMEOUT_MS,
          windowsHide: true,
          maxBuffer: 10 * 1024 * 1024,
          encoding: 'utf8',
        }
      );
    } catch (wslError: any) {
      if (wslError?.code === 'ENOENT') {
        return await run('git', gitArgs, {
          cwd,
          timeout: EXEC_TIMEOUT_MS,
          windowsHide: true,
          maxBuffer: 10 * 1024 * 1024,
          encoding: 'utf8',
        });
      }
      throw wslError;
    }
  }

  return await run('git', gitArgs, {
    cwd,
    timeout: EXEC_TIMEOUT_MS,
    windowsHide: true,
    maxBuffer: 10 * 1024 * 1024,
    encoding: 'utf8',
  });
}

async function runGit(args: string[], cwd: string, trim = true): Promise<string | null> {
  try {
    const stdout = await executeGit(args, cwd);
    return trim ? stdout.trim() : stdout;
  } catch {
    return null;
  }
}

export async function runGitStrict(args: string[], cwd: string): Promise<string> {
  try {
    return await executeGit(args, cwd);
  } catch (cause: any) {
    const error: any = new Error((cause?.stderr || cause?.message || 'Git command failed').trim());
    error.code = 'GIT_FAILED';
    error.details = { args, exitCode: cause?.code, signal: cause?.signal };
    throw error;
  }
}

export async function checkIsGitRepo(cwd: string): Promise<{ isRepo: boolean; rootPath?: string }> {
  const wslInfo = parseWslPath(cwd);
  const root = await runGit(['rev-parse', '--show-toplevel'], cwd);
  if (!root) return { isRepo: false };
  if (wslInfo && root.startsWith('/')) {
    return { isRepo: true, rootPath: toWslUncPath(root, wslInfo.uncPrefix) };
  }
  return { isRepo: true, rootPath: path.normalize(root) };
}

export async function getCurrentBranch(cwd: string): Promise<string | null> {
  const branch = await runGit(['branch', '--show-current'], cwd);
  if (branch && branch.length > 0) return branch;
  const rev = await runGit(['rev-parse', '--short', 'HEAD'], cwd);
  return rev ? `HEAD (${rev})` : null;
}

function statusCode(code: string): GitFileStatusCode {
  if (code === 'A' || code === '?') return code === '?' ? 'untracked' : 'added';
  if (code === 'D') return 'deleted';
  if (code === 'R' || code === 'C') return 'renamed';
  return 'modified';
}

interface Numstat {
  path: string;
  additions: number;
  deletions: number;
}

function parseNumstatCount(value: string): number {
  return value === '-' ? 0 : Number.parseInt(value, 10) || 0;
}

function parseNumstatZ(output: string): Numstat[] {
  const entries = output.split('\0');
  const result: Numstat[] = [];
  for (let index = 0; index < entries.length; index++) {
    if (!entries[index]) continue;
    const firstTab = entries[index].indexOf('\t');
    const secondTab = entries[index].indexOf('\t', firstTab + 1);
    if (firstTab < 0 || secondTab < 0) continue;
    const additions = parseNumstatCount(entries[index].slice(0, firstTab));
    const deletions = parseNumstatCount(entries[index].slice(firstTab + 1, secondTab));
    let filePath = entries[index].slice(secondTab + 1);
    if (!filePath) {
      const oldPath = entries[++index];
      const newPath = entries[++index];
      filePath = newPath || oldPath || '';
    }
    if (filePath) result.push({ path: filePath, additions, deletions });
  }
  return result;
}

function parseNumstat(output: string): { additions: number; deletions: number } {
  const firstTab = output.indexOf('\t');
  const secondTab = output.indexOf('\t', firstTab + 1);
  if (firstTab < 0 || secondTab < 0) return { additions: 0, deletions: 0 };
  return {
    additions: parseNumstatCount(output.slice(0, firstTab)),
    deletions: parseNumstatCount(output.slice(firstTab + 1, secondTab)),
  };
}

async function hasHead(cwd: string): Promise<boolean> {
  return (await runGit(['rev-parse', '--verify', 'HEAD'], cwd)) !== null;
}

async function getNoIndexNumstat(cwd: string, filePath: string): Promise<Numstat> {
  // Unreadable entries (e.g. a directory or a file removed mid-scan) must not fail the whole status.
  try {
    const output = await executeGit(
      ['diff', '--no-index', '--numstat', '--', '/dev/null', filePath],
      cwd,
      [1]
    );
    return { path: filePath, ...parseNumstat(output) };
  } catch {
    return { path: filePath, additions: 0, deletions: 0 };
  }
}

function parseStatus(cwd: string, statusOutput: string): {
  changes: Map<string, GitFileChange>;
  renameSources: Map<string, string>;
} {
  const changes = new Map<string, GitFileChange>();
  const renameSources = new Map<string, string>();
  const entries = statusOutput.split('\0');
  for (let index = 0; index < entries.length; index++) {
    const entry = entries[index];
    if (!entry || entry.length < 4) continue;
    const indexCode = entry[0];
    const worktreeCode = entry[1];
    const filePath = entry.slice(3);
    const staged = indexCode !== ' ' && indexCode !== '?';
    const unstaged = worktreeCode !== ' ' || indexCode === '?';
    const code = worktreeCode !== ' ' && worktreeCode !== '?' ? worktreeCode : indexCode;
    changes.set(filePath, {
      path: filePath,
      status: statusCode(code),
      staged,
      unstaged,
      stagedStatus: staged ? indexCode : null,
      unstagedStatus: unstaged ? worktreeCode : null,
      additions: 0,
      deletions: 0,
    });
    if (indexCode === 'R' || indexCode === 'C' || worktreeCode === 'R' || worktreeCode === 'C') {
      const sourcePath = entries[++index];
      if (sourcePath) renameSources.set(filePath, sourcePath);
    }
  }
  return { changes, renameSources };
}

export async function getGitStatus(cwd: string): Promise<GitStatusResult> {
  const { isRepo, rootPath } = await checkIsGitRepo(cwd);
  if (!isRepo || !rootPath) {
    return { isRepository: false, files: [], totalAdditions: 0, totalDeletions: 0 };
  }

  const branch = await getCurrentBranch(cwd);
  const statusOutput = await runGit(['status', '--porcelain=v1', '-z', '--untracked-files=all'], cwd, false) ?? '';
  const { changes } = parseStatus(cwd, statusOutput);
  const headExists = await hasHead(cwd);
  let numstats: Numstat[] = [];
  if (headExists) {
    const output = await runGitStrict(['diff', '--numstat', '-z', 'HEAD'], cwd);
    numstats = parseNumstatZ(output);
    for (const change of changes.values()) {
      if (change.status !== 'untracked') continue;
      const fullPath = path.resolve(cwd, ...change.path.split('/'));
      if (fs.existsSync(fullPath)) numstats.push(await getNoIndexNumstat(cwd, change.path));
    }
  } else {
    for (const change of changes.values()) {
      const fullPath = path.resolve(cwd, ...change.path.split('/'));
      if (fs.existsSync(fullPath)) numstats.push(await getNoIndexNumstat(cwd, change.path));
    }
  }

  let totalAdditions = 0;
  let totalDeletions = 0;
  for (const stat of numstats) {
    totalAdditions += stat.additions;
    totalDeletions += stat.deletions;
    const existing = changes.get(stat.path);
    if (existing) {
      existing.additions += stat.additions;
      existing.deletions += stat.deletions;
    }
  }

  return {
    isRepository: true,
    rootPath,
    branch: branch ?? undefined,
    files: Array.from(changes.values()),
    totalAdditions,
    totalDeletions,
  };
}

export async function getStagedPaths(cwd: string): Promise<string[]> {
  const output = await runGitStrict(['diff', '--cached', '--name-only', '-z'], cwd);
  return output.split('\0').filter(Boolean).sort();
}

export async function getGitDiff(cwd: string, filePath?: string): Promise<string> {
  if (!filePath) {
    if (!(await hasHead(cwd))) return '';
    return (await runGitStrict(['diff', 'HEAD'], cwd)).trim();
  }

  const normalizedPath = filePath.replace(/\\/g, '/');
  const status = await getGitStatus(cwd);
  const change = status.files.find((item) => item.path === normalizedPath);
  const headExists = await hasHead(cwd);
  const args = ['diff', ...(headExists ? ['HEAD'] : [])];
  if (headExists) {
    const paths = [normalizedPath];
    if (change?.status === 'renamed') {
      const statusOutput = await runGit(['status', '--porcelain=v1', '-z', '--untracked-files=all'], cwd, false) ?? '';
      const source = parseStatus(cwd, statusOutput).renameSources.get(normalizedPath);
      if (source) paths.unshift(source);
    }
    args.push('--', ...paths.map((value) => `:(literal)${value}`));
    const diff = await runGitStrict(args, cwd);
    if (diff) return diff.trim();
  }

  const canUseNoIndex = headExists
    ? change?.status === 'untracked'
    : change !== undefined;
  const fullPath = path.resolve(cwd, ...normalizedPath.split('/'));
  if (!canUseNoIndex || !fs.existsSync(fullPath)) return '';
  return (await executeGit(
    ['diff', '--no-index', '--', '/dev/null', normalizedPath],
    cwd,
    [1]
  )).trim();
}
