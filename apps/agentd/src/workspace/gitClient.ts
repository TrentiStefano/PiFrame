import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

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

async function runGit(args: string[], cwd: string, trim = true): Promise<string | null> {
  try {
    const { stdout } = await execFileAsync('git', args, {
      cwd,
      timeout: EXEC_TIMEOUT_MS,
      windowsHide: true,
      maxBuffer: 10 * 1024 * 1024,
      encoding: 'utf8',
    });
    return trim ? stdout.trim() : stdout;
  } catch {
    return null;
  }
}

export async function runGitStrict(args: string[], cwd: string): Promise<string> {
  try {
    const { stdout } = await execFileAsync('git', args, {
      cwd,
      timeout: EXEC_TIMEOUT_MS,
      windowsHide: true,
      maxBuffer: 10 * 1024 * 1024,
      encoding: 'utf8',
    });
    return stdout;
  } catch (cause: any) {
    const error: any = new Error((cause?.stderr || cause?.message || 'Git command failed').trim());
    error.code = 'GIT_FAILED';
    error.details = { args, exitCode: cause?.code, signal: cause?.signal };
    throw error;
  }
}

export async function checkIsGitRepo(cwd: string): Promise<{ isRepo: boolean; rootPath?: string }> {
  const root = await runGit(['rev-parse', '--show-toplevel'], cwd);
  if (!root) return { isRepo: false };
  return { isRepo: true, rootPath: root };
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
  const args = ['diff', 'HEAD'];
  if (filePath) args.push('--', filePath);
  const diff = await runGit(args, cwd);
  if (diff && diff.length > 0) return diff;
  const unstagedArgs = ['diff'];
  if (filePath) unstagedArgs.push('--', filePath);
  return (await runGit(unstagedArgs, cwd)) ?? '';
}
