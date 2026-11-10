import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import * as fs from 'node:fs';
import * as path from 'node:path';
import type {
  WorkspaceBranchInfo,
  WorkspaceListBranchesResult,
  WorkspaceSwitchBranchResult
} from '@piframe/pcp-ts';

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
  acceptedExitCodes: number[] = [],
  timeoutMs: number = EXEC_TIMEOUT_MS
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
          timeout: timeoutMs,
          windowsHide: true,
          maxBuffer: 10 * 1024 * 1024,
          encoding: 'utf8',
        }
      );
    } catch (wslError: any) {
      if (wslError?.code === 'ENOENT') {
        return await run('git', gitArgs, {
          cwd,
          timeout: timeoutMs,
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
    timeout: timeoutMs,
    windowsHide: true,
    maxBuffer: 10 * 1024 * 1024,
    encoding: 'utf8',
    // Never block the daemon on a terminal credential prompt.
    env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
  });
}

async function runGit(args: string[], cwd: string, trim = true, timeoutMs = EXEC_TIMEOUT_MS): Promise<string | null> {
  try {
    const stdout = await executeGit(args, cwd, [], timeoutMs);
    return trim ? stdout.trim() : stdout;
  } catch {
    return null;
  }
}

export async function runGitStrict(args: string[], cwd: string, timeoutMs = EXEC_TIMEOUT_MS): Promise<string> {
  try {
    return await executeGit(args, cwd, [], timeoutMs);
  } catch (cause: any) {
    const rawStderr = (cause?.stderr || cause?.message || 'Git command failed').trim();
    const error: any = new Error(rawStderr);
    error.code = 'GIT_FAILED';
    error.stderr = rawStderr;
    error.details = { args, exitCode: cause?.code, signal: cause?.signal };
    throw error;
  }
}

export const REMOTE_ACTIONS = ['fetch', 'pull', 'push', 'sync'];
const REMOTE_TIMEOUT_MS = 120_000;

/** fetch / pull (fast-forward only) / push (publishes a branch without upstream) / sync = pull then push. */
export async function runRemoteGitAction(cwd: string, action: string): Promise<void> {
  const git = (args: string[]) => runGitStrict(args, cwd, REMOTE_TIMEOUT_MS);
  const hasUpstream = await runGit(['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'], cwd);
  const pull = () => git(['pull', '--ff-only', '--no-edit']);
  const push = () => git(hasUpstream ? ['push'] : ['push', '--set-upstream', 'origin', 'HEAD']);
  if (action === 'fetch') await git(['fetch', '--all', '--prune']);
  else if (action === 'pull') await pull();
  else if (action === 'push') await push();
  else {
    if (hasUpstream) await pull();
    await push();
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

/**
 * Counts the lines of an untracked file the way `git diff --no-index --numstat /dev/null <file>` does, in-process.
 * Spawning git per file blocks the daemon's event loop on Windows, which stalls every other request.
 */
async function countUntrackedLines(cwd: string, filePath: string): Promise<Numstat> {
  // Unreadable entries (e.g. a directory or a file removed mid-scan) must not fail the whole status.
  try {
    const content = await fs.promises.readFile(path.resolve(cwd, ...filePath.split('/')));
    // git treats a NUL in the first 8000 bytes as binary and reports no line counts.
    if (content.subarray(0, 8000).includes(0)) return { path: filePath, additions: 0, deletions: 0 };
    let lines = 0;
    for (const byte of content) {
      if (byte === 0x0a) lines++;
    }
    if (content.length > 0 && content[content.length - 1] !== 0x0a) lines++;
    return { path: filePath, additions: lines, deletions: 0 };
  } catch {
    return { path: filePath, additions: 0, deletions: 0 };
  }
}

async function getNoIndexNumstats(cwd: string, filePaths: string[]): Promise<Numstat[]> {
  const numstats: Numstat[] = [];
  const batchSize = 16;
  for (let i = 0; i < filePaths.length; i += batchSize) {
    numstats.push(
      ...await Promise.all(
        filePaths.slice(i, i + batchSize).map((filePath) => countUntrackedLines(cwd, filePath))
      )
    );
  }
  return numstats;
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

/**
 * Reads the "## ..." header of `git status --porcelain -b -z`. Porcelain labels are not translated.
 * `branch` is null when HEAD is detached; the caller then asks git for the short commit id.
 */
export function parseBranchHeader(output: string): { length: number; branch: string | null; unborn: boolean } | null {
  if (!output.startsWith('## ')) return null;
  const end = output.indexOf('\0');
  const text = output.slice(3, end < 0 ? undefined : end);
  const length = end < 0 ? output.length : end + 1;
  const unbornMatch = text.match(/^(?:No commits yet on|Initial commit on) (.+)$/);
  if (unbornMatch) return { length, branch: unbornMatch[1], unborn: true };
  if (text.startsWith('HEAD (no branch)')) return { length, branch: null, unborn: false };
  return { length, branch: text.split('...')[0].split(' [')[0], unborn: false };
}

export async function getGitStatus(cwd: string): Promise<GitStatusResult> {
  const { isRepo, rootPath } = await checkIsGitRepo(cwd);
  if (!isRepo || !rootPath) {
    return { isRepository: false, files: [], totalAdditions: 0, totalDeletions: 0 };
  }

  // `-b` adds a "## <branch>" header, which replaces two extra git processes (branch and HEAD lookups).
  // Each git process is slow on Windows and WSL, and the status is refreshed often.
  const statusOutput = await runGit(['status', '--porcelain=v1', '-z', '-b', '--untracked-files=all'], cwd, false) ?? '';
  const header = parseBranchHeader(statusOutput);
  const { changes } = parseStatus(cwd, header ? statusOutput.slice(header.length) : statusOutput);
  const branch = header?.branch ?? await getCurrentBranch(cwd);
  const headExists = header ? !header.unborn : await hasHead(cwd);
  let numstats: Numstat[] = [];
  if (headExists) {
    const output = await runGitStrict(['diff', '--numstat', '-z', 'HEAD'], cwd);
    numstats = parseNumstatZ(output);
    const untrackedPaths = Array.from(changes.values())
      .filter((change) => change.status === 'untracked')
      .map((change) => change.path);
    numstats.push(...await getNoIndexNumstats(cwd, untrackedPaths));
  } else {
    numstats = await getNoIndexNumstats(cwd, Array.from(changes.keys()));
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
  const statusOutput = await runGit(
    ['status', '--porcelain=v1', '-z', '--untracked-files=all', '--', `:(literal)${normalizedPath}`],
    cwd,
    false
  ) ?? '';
  let { changes, renameSources } = parseStatus(cwd, statusOutput);
  let change = changes.get(normalizedPath);
  const headExists = await hasHead(cwd);
  if (headExists && change?.stagedStatus === 'A') {
    const fullStatusOutput = await runGit(
      ['status', '--porcelain=v1', '-z', '--untracked-files=all'],
      cwd,
      false
    ) ?? '';
    ({ changes, renameSources } = parseStatus(cwd, fullStatusOutput));
    change = changes.get(normalizedPath) ?? change;
  }
  const args = ['diff', ...(headExists ? ['HEAD'] : [])];
  if (headExists) {
    const paths = [normalizedPath];
    if (change?.status === 'renamed') {
      const source = renameSources.get(normalizedPath);
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

// -----------------------------------------------------------------------------
// Branch Operations
// -----------------------------------------------------------------------------

export interface GitDirtyState {
  isDirty: boolean;
  changedFiles: number;
  untrackedFiles: number;
}

export type GitSwitchHooks = {
  injectBeforeStashPush?: () => Promise<void>;
  injectSwitchFailure?: (branch: string) => Promise<void>;
  injectPopFailure?: () => Promise<void>;
};

export async function getCurrentBranchName(cwd: string): Promise<string | null> {
  const branch = await runGit(['symbolic-ref', '--short', '-q', 'HEAD'], cwd);
  return branch && branch.length > 0 ? branch : null;
}

export async function getHeadShortSha(cwd: string): Promise<string | null> {
  return await runGit(['rev-parse', '--short', 'HEAD'], cwd);
}

export async function isDetachedHead(cwd: string): Promise<boolean> {
  const branch = await getCurrentBranchName(cwd);
  if (branch !== null) return false;
  return await hasHead(cwd);
}

export async function validateBranchName(cwd: string, name: unknown): Promise<string> {
  if (typeof name !== 'string') {
    const err: any = new Error('Branch name must be a string.');
    err.code = 'BRANCH_INVALID_NAME';
    throw err;
  }
  if (
    name.length === 0 ||
    name.length > 255 ||
    name.startsWith('-') ||
    /[\s\x00-\x1f\x7f]/.test(name) ||
    name === 'HEAD' ||
    name.includes('@{')
  ) {
    const err: any = new Error(`Invalid branch name: '${name}'.`);
    err.code = 'BRANCH_INVALID_NAME';
    throw err;
  }

  try {
    const output = await executeGit(['check-ref-format', '--branch', name], cwd);
    if (output.trim() !== name) {
      const err: any = new Error(`Invalid branch name: '${name}'.`);
      err.code = 'BRANCH_INVALID_NAME';
      throw err;
    }
  } catch {
    const err: any = new Error(`Invalid branch name: '${name}'.`);
    err.code = 'BRANCH_INVALID_NAME';
    throw err;
  }

  return name;
}

export async function verifyBranchExists(cwd: string, name: string): Promise<boolean> {
  const res = await runGit(['rev-parse', '--verify', '--quiet', `refs/heads/${name}`], cwd);
  return res !== null;
}

export async function getGitDirtyState(cwd: string): Promise<GitDirtyState> {
  const statusOutput = (await runGit(['status', '--porcelain=v1', '-z'], cwd, false)) ?? '';
  let changedFiles = 0;
  let untrackedFiles = 0;
  const entries = statusOutput.split('\0');
  for (let index = 0; index < entries.length; index++) {
    const entry = entries[index];
    if (!entry || entry.length < 3) continue;
    const indexCode = entry[0];
    const worktreeCode = entry[1];
    if (indexCode === '?' && worktreeCode === '?') {
      untrackedFiles++;
    } else {
      changedFiles++;
    }
    if (indexCode === 'R' || indexCode === 'C' || worktreeCode === 'R' || worktreeCode === 'C') {
      index++;
    }
  }
  return {
    isDirty: changedFiles + untrackedFiles > 0,
    changedFiles,
    untrackedFiles,
  };
}

export async function listGitBranches(cwd: string): Promise<WorkspaceListBranchesResult> {
  const { isRepo, rootPath } = await checkIsGitRepo(cwd);
  if (!isRepo || !rootPath) {
    throw Object.assign(new Error('Working directory is not inside a Git repository.'), {
      code: 'WORKSPACE_NOT_REPOSITORY',
    });
  }

  const currentBranch = await getCurrentBranchName(rootPath);
  const headShortSha = await getHeadShortSha(rootPath);
  const headExists = await hasHead(rootPath);
  const detached = headExists && currentBranch === null;

  if (!headExists) {
    return {
      branches: [],
      currentBranch,
      detached: false,
      headShortSha: null,
    };
  }

  const output = await runGit(
    [
      'for-each-ref',
      '--format=%(refname:short)%00%(HEAD)%00%(upstream:short)%00%(upstream:track,nobracket)%00%(committerdate:unix)',
      'refs/heads',
    ],
    rootPath,
    false
  );

  const branches: WorkspaceBranchInfo[] = [];
  if (output) {
    const lines = output.split(/\r?\n/).filter(Boolean);
    for (const line of lines) {
      const parts = line.split('\0');
      if (parts.length < 5) continue;
      const name = parts[0];
      const headFlag = parts[1].trim();
      const upstreamRaw = parts[2].trim();
      const trackRaw = parts[3].trim();
      const dateRaw = parts[4].trim();

      const isCurrent = currentBranch !== null && (name === currentBranch || headFlag === '*');
      const upstream = upstreamRaw.length > 0 ? upstreamRaw : null;
      let ahead: number | null = null;
      let behind: number | null = null;

      if (upstream) {
        if (trackRaw === 'gone') {
          ahead = null;
          behind = null;
        } else {
          const aheadMatch = trackRaw.match(/ahead\s+(\d+)/);
          const behindMatch = trackRaw.match(/behind\s+(\d+)/);
          ahead = aheadMatch ? parseInt(aheadMatch[1], 10) : 0;
          behind = behindMatch ? parseInt(behindMatch[1], 10) : 0;
        }
      }

      const parsedDate = parseInt(dateRaw, 10);
      const lastCommitUnix = Number.isNaN(parsedDate) ? null : parsedDate;

      branches.push({
        name,
        isCurrent,
        upstream,
        ahead,
        behind,
        lastCommitUnix,
      });
    }
  }

  // Current first, then by lastCommit desc, then alphabetical
  branches.sort((a, b) => {
    if (a.isCurrent && !b.isCurrent) return -1;
    if (!a.isCurrent && b.isCurrent) return 1;
    const timeA = a.lastCommitUnix ?? -1;
    const timeB = b.lastCommitUnix ?? -1;
    if (timeB !== timeA) return timeB - timeA;
    return a.name.localeCompare(b.name);
  });

  return {
    branches,
    currentBranch,
    detached,
    headShortSha,
  };
}

async function resolveStashRefBySha(cwd: string, targetSha: string): Promise<string | null> {
  const output = (await runGit(['stash', 'list', '--format=%gd%x00%H%x00%gs'], cwd, false, 30000)) ?? '';
  const lines = output.split(/\r?\n/).filter(Boolean);
  for (const line of lines) {
    const parts = line.split('\0');
    if (parts.length >= 2) {
      const ref = parts[0].trim();
      const sha = parts[1].trim();
      if (sha === targetSha) {
        return ref;
      }
    }
  }
  return null;
}

export async function switchGitBranch(
  cwd: string,
  branch: string,
  onDirty: 'block' | 'stash' = 'block',
  hooks?: GitSwitchHooks
): Promise<WorkspaceSwitchBranchResult> {
  const current = await getCurrentBranchName(cwd);
  if (current === branch) {
    return {
      currentBranch: branch,
      stashed: false,
      stashMessage: null,
    };
  }

  const dirtyState = await getGitDirtyState(cwd);
  if (dirtyState.isDirty) {
    if (onDirty === 'block') {
      const err: any = new Error(
        `Working directory has uncommitted changes (${dirtyState.changedFiles} changed, ${dirtyState.untrackedFiles} untracked).`
      );
      err.code = 'WORKSPACE_DIRTY';
      err.details = {
        changedFiles: dirtyState.changedFiles,
        untrackedFiles: dirtyState.untrackedFiles,
      };
      throw err;
    }

    // onDirty === 'stash'
    if (hooks?.injectBeforeStashPush) {
      await hooks.injectBeforeStashPush();
    }
    const isoTime = new Date().toISOString();
    const stashMessage = `piframe: before switching to ${branch} (${isoTime})`;
    await runGitStrict(['stash', 'push', '--include-untracked', '-m', stashMessage], cwd, 30000);

    const stashSha = await runGit(['rev-parse', '-q', '--verify', 'refs/stash'], cwd, true, 30000);
    let createdStashSha: string | null = null;
    let effectiveStashMessage: string | null = null;

    if (stashSha) {
      const stashListOutput = (await runGit(['stash', 'list', '--format=%gd%x00%H%x00%gs'], cwd, false, 30000)) ?? '';
      const lines = stashListOutput.split(/\r?\n/).filter(Boolean);
      for (const line of lines) {
        const parts = line.split('\0');
        if (parts.length >= 3) {
          const sha = parts[1].trim();
          const subject = parts[2].trim();
          if (sha === stashSha && subject.includes(stashMessage)) {
            createdStashSha = stashSha;
            effectiveStashMessage = stashMessage;
            break;
          }
        }
      }
    }

    try {
      if (hooks?.injectSwitchFailure) {
        await hooks.injectSwitchFailure(branch);
      } else {
        await runGitStrict(['switch', '--no-guess', '--', branch], cwd, 30000);
      }
    } catch (switchError: any) {
      const rawStderr = (switchError.stderr || switchError.message || '').trim();
      const stderrTrimmed = rawStderr.slice(0, 2048);

      if (!createdStashSha) {
        const err: any = new Error(`Failed to switch to branch '${branch}': ${stderrTrimmed}`);
        err.code = 'BRANCH_SWITCH_FAILED';
        err.details = { stderr: stderrTrimmed };
        throw err;
      }

      const targetRef = await resolveStashRefBySha(cwd, createdStashSha);
      if (!targetRef) {
        const err: any = new Error(
          `Failed to switch to branch '${branch}', and stash could not be restored: ${stderrTrimmed}`
        );
        err.code = 'BRANCH_SWITCH_FAILED';
        err.details = {
          stderr: stderrTrimmed,
          stashRetained: true,
          stashMessage: effectiveStashMessage,
        };
        throw err;
      }

      try {
        if (hooks?.injectPopFailure) {
          await hooks.injectPopFailure();
        } else {
          await runGitStrict(['stash', 'pop', targetRef], cwd, 30000);
        }
      } catch (popError: any) {
        const err: any = new Error(
          `Failed to switch to branch '${branch}', and stash could not be restored: ${stderrTrimmed}`
        );
        err.code = 'BRANCH_SWITCH_FAILED';
        err.details = {
          stderr: stderrTrimmed,
          stashRetained: true,
          stashMessage: effectiveStashMessage,
        };
        throw err;
      }

      const err: any = new Error(`Failed to switch to branch '${branch}': ${stderrTrimmed}`);
      err.code = 'BRANCH_SWITCH_FAILED';
      err.details = { stderr: stderrTrimmed };
      throw err;
    }

    return {
      currentBranch: branch,
      stashed: createdStashSha !== null,
      stashMessage: effectiveStashMessage,
    };
  }

  // Not dirty
  try {
    if (hooks?.injectSwitchFailure) {
      await hooks.injectSwitchFailure(branch);
    } else {
      await runGitStrict(['switch', '--no-guess', '--', branch], cwd, 30000);
    }
  } catch (switchError: any) {
    const rawStderr = (switchError.stderr || switchError.message || '').trim();
    const stderrTrimmed = rawStderr.slice(0, 2048);
    const err: any = new Error(`Failed to switch to branch '${branch}': ${stderrTrimmed}`);
    err.code = 'BRANCH_SWITCH_FAILED';
    err.details = { stderr: stderrTrimmed };
    throw err;
  }

  return {
    currentBranch: branch,
    stashed: false,
    stashMessage: null,
  };
}
