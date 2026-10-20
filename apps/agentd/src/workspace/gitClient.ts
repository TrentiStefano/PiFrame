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

async function executeGit(args: string[], cwd: string): Promise<string> {
  const wslInfo = parseWslPath(cwd);
  const gitArgs = ['-c', 'safe.directory=*', ...args];

  if (wslInfo) {
    try {
      const { stdout } = await execFileAsync(
        'wsl.exe',
        ['-d', wslInfo.distro, '--cd', wslInfo.linuxPath, 'git', ...gitArgs],
        {
          timeout: EXEC_TIMEOUT_MS,
          windowsHide: true,
          maxBuffer: 10 * 1024 * 1024,
          encoding: 'utf8',
        }
      );
      return stdout;
    } catch (wslError: any) {
      if (wslError?.code === 'ENOENT') {
        const { stdout } = await execFileAsync('git', gitArgs, {
          cwd,
          timeout: EXEC_TIMEOUT_MS,
          windowsHide: true,
          maxBuffer: 10 * 1024 * 1024,
          encoding: 'utf8',
        });
        return stdout;
      }
      throw wslError;
    }
  }

  const { stdout } = await execFileAsync('git', gitArgs, {
    cwd,
    timeout: EXEC_TIMEOUT_MS,
    windowsHide: true,
    maxBuffer: 10 * 1024 * 1024,
    encoding: 'utf8',
  });
  return stdout;
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

export async function getGitStatus(cwd: string): Promise<GitStatusResult> {
  const { isRepo, rootPath } = await checkIsGitRepo(cwd);
  if (!isRepo || !rootPath) {
    return { isRepository: false, files: [], totalAdditions: 0, totalDeletions: 0 };
  }

  const branch = await getCurrentBranch(cwd);
  const statusOutput = await runGit(['status', '--porcelain=v1', '-z'], cwd, false);
  const changes = new Map<string, GitFileChange>();
  if (statusOutput) {
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
      if (code === 'R' || code === 'C') index++;
    }
  }

  const numstatOutput = await runGit(['diff', '--numstat', 'HEAD'], cwd);
  let totalAdditions = 0;
  let totalDeletions = 0;
  if (numstatOutput) {
    for (const line of numstatOutput.split('\n')) {
      const parts = line.split('\t');
      if (parts.length < 3) continue;
      const additions = Number.parseInt(parts[0], 10) || 0;
      const deletions = Number.parseInt(parts[1], 10) || 0;
      totalAdditions += additions;
      totalDeletions += deletions;
      const existing = changes.get(parts.slice(2).join('\t'));
      if (existing) {
        existing.additions = additions;
        existing.deletions = deletions;
      }
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
  const normalizedPath = filePath ? filePath.replace(/\\/g, '/') : undefined;
  const args = ['diff', 'HEAD'];
  if (normalizedPath) args.push('--', normalizedPath);
  const diff = await runGit(args, cwd);
  if (diff && diff.length > 0) return diff;
  const unstagedArgs = ['diff'];
  if (normalizedPath) unstagedArgs.push('--', normalizedPath);
  const unstagedDiff = await runGit(unstagedArgs, cwd);
  if (unstagedDiff && unstagedDiff.length > 0) return unstagedDiff;

  if (normalizedPath) {
    try {
      const fullPath = path.resolve(cwd, ...normalizedPath.split('/'));
      if (fs.existsSync(fullPath)) {
        try {
          const out = await executeGit(['diff', '--no-index', '--', '/dev/null', normalizedPath], cwd);
          if (out && out.length > 0) return out.trim();
        } catch (err: any) {
          const stdout = err?.stdout;
          if (typeof stdout === 'string' && stdout.trim().length > 0) {
            return stdout.trim();
          }
        }
      }
    } catch {}
  }

  return '';
}
