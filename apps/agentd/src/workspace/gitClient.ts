import { execFile } from 'child_process';
import { promisify } from 'util';

const execFileAsync = promisify(execFile);

export type GitFileStatusCode = 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked';

export interface GitFileChange {
  path: string;
  status: GitFileStatusCode;
  staged: boolean;
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

async function runGit(args: string[], cwd: string): Promise<string | null> {
  try {
    const { stdout } = await execFileAsync('git', args, {
      cwd,
      timeout: EXEC_TIMEOUT_MS,
      windowsHide: true,
      maxBuffer: 10 * 1024 * 1024, // 10MB limit
      encoding: 'utf8',
    });
    return stdout.trim();
  } catch {
    return null;
  }
}

export async function checkIsGitRepo(cwd: string): Promise<{ isRepo: boolean; rootPath?: string }> {
  const root = await runGit(['rev-parse', '--show-toplevel'], cwd);
  if (!root) {
    return { isRepo: false };
  }
  return { isRepo: true, rootPath: root };
}

export async function getCurrentBranch(cwd: string): Promise<string | null> {
  const branch = await runGit(['branch', '--show-current'], cwd);
  if (branch && branch.length > 0) return branch;

  // Detached HEAD fallback
  const rev = await runGit(['rev-parse', '--short', 'HEAD'], cwd);
  return rev ? `HEAD (${rev})` : null;
}

export async function getGitStatus(cwd: string): Promise<GitStatusResult> {
  const { isRepo, rootPath } = await checkIsGitRepo(cwd);
  if (!isRepo || !rootPath) {
    return {
      isRepository: false,
      files: [],
      totalAdditions: 0,
      totalDeletions: 0,
    };
  }

  const branch = await getCurrentBranch(cwd);

  // 1. Parse status --porcelain=v2
  const statusOutput = await runGit(['status', '--porcelain=v2'], cwd);
  const fileChangesMap = new Map<string, GitFileChange>();

  if (statusOutput) {
    const lines = statusOutput.split('\n');
    for (const line of lines) {
      if (!line || line.length < 2) continue;
      // 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
      // 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><sep><origPath>
      // ? <path>
      // ! <path>
      if (line.startsWith('1 ')) {
        const parts = line.split(' ');
        const xy = parts[1];
        const filePath = parts.slice(8).join(' ');
        const staged = xy[0] !== '.';
        const code = xy[1] !== '.' ? xy[1] : xy[0];

        let status: GitFileStatusCode = 'modified';
        if (code === 'A') status = 'added';
        else if (code === 'D') status = 'deleted';
        else if (code === 'R') status = 'renamed';

        fileChangesMap.set(filePath, {
          path: filePath,
          status,
          staged,
          additions: 0,
          deletions: 0,
        });
      } else if (line.startsWith('2 ')) {
        const parts = line.split(' ');
        const xy = parts[1];
        const pathPart = parts.slice(9).join(' ');
        const [filePath] = pathPart.split('\t');
        fileChangesMap.set(filePath, {
          path: filePath,
          status: 'renamed',
          staged: xy[0] !== '.',
          additions: 0,
          deletions: 0,
        });
      } else if (line.startsWith('? ')) {
        const filePath = line.substring(2).trim();
        fileChangesMap.set(filePath, {
          path: filePath,
          status: 'untracked',
          staged: false,
          additions: 0,
          deletions: 0,
        });
      }
    }
  }

  // 2. Parse diff --numstat for additions & deletions count
  const numstatOutput = await runGit(['diff', '--numstat', 'HEAD'], cwd);
  let totalAdditions = 0;
  let totalDeletions = 0;

  if (numstatOutput) {
    const lines = numstatOutput.split('\n');
    for (const line of lines) {
      const parts = line.split('\t');
      if (parts.length >= 3) {
        const adds = parseInt(parts[0], 10) || 0;
        const dels = parseInt(parts[1], 10) || 0;
        const filePath = parts[2].trim();

        totalAdditions += adds;
        totalDeletions += dels;

        const existing = fileChangesMap.get(filePath);
        if (existing) {
          existing.additions = adds;
          existing.deletions = dels;
        }
      }
    }
  }

  return {
    isRepository: true,
    rootPath,
    branch: branch ?? undefined,
    files: Array.from(fileChangesMap.values()),
    totalAdditions,
    totalDeletions,
  };
}

export async function getGitDiff(cwd: string, filePath?: string): Promise<string> {
  const args = ['diff', 'HEAD'];
  if (filePath) {
    args.push('--', filePath);
  }
  const diff = await runGit(args, cwd);
  if (diff && diff.length > 0) return diff;

  // If no diff against HEAD (e.g. untracked file or new commit), try unstaged diff
  const unstagedArgs = ['diff'];
  if (filePath) {
    unstagedArgs.push('--', filePath);
  }
  const unstaged = await runGit(unstagedArgs, cwd);
  return unstaged ?? '';
}
