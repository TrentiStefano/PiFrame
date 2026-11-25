/**
 * I/O for the verify worktree folders: reads the sibling folders and their git metadata, and deletes folder trees
 * (long paths and read-only files included). The decisions are pure and live in tools/guardrails/src/verify-worktrees.mjs;
 * tools/scripts/verify-ci.mjs calls both.
 */
import { execFileSync, spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';

const IS_WIN = process.platform === 'win32';
// Windows only sees paths over 260 characters with the \\?\ prefix, and Node's fs refuses to delete them without it.
const LONG_PATH_PREFIX = '\\\\?\\';
/** Two root files that only this repository has together: a folder holding both is a copy of it. */
const REPO_MARKERS = ['pnpm-workspace.yaml', 'AGENTS.md'];

export function git(cwd, ...gitArgs) {
  return execFileSync('git', gitArgs, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

export function longPath(dir) {
  const abs = path.resolve(dir);
  return IS_WIN && !abs.startsWith(LONG_PATH_PREFIX) ? `${LONG_PATH_PREFIX}${abs}` : abs;
}

export function normalizePath(p) {
  const abs = path.resolve(p);
  return IS_WIN ? abs.toLowerCase() : abs;
}

export function folderExists(dir) {
  return fs.existsSync(longPath(dir));
}

/** Deletes a folder tree. Returns true when the folder is gone. Falls back to PowerShell for Windows long paths. */
export function removeFolder(dir) {
  if (!folderExists(dir)) return true;
  try {
    fs.rmSync(longPath(dir), { recursive: true, force: true, maxRetries: 3, retryDelay: 200 });
  } catch {
    // Fall through to PowerShell below.
  }
  if (folderExists(dir) && IS_WIN) {
    const target = longPath(dir).replace(/'/g, "''");
    spawnSync(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', `Remove-Item -LiteralPath '${target}' -Recurse -Force`],
      { stdio: 'ignore' }
    );
  }
  return !folderExists(dir);
}

export function worktreePaths(repo) {
  return git(repo, 'worktree', 'list', '--porcelain')
    .split(/\r?\n/)
    .filter((line) => line.startsWith('worktree '))
    .map((line) => line.slice('worktree '.length));
}

/** True when the folder's `.git` file points into this repository's worktrees, also after git has forgotten it. */
function linkedToRepository(dir, gitDir) {
  try {
    const target = fs
      .readFileSync(path.join(longPath(dir), '.git'), 'utf8')
      .match(/^gitdir:\s*(.+)$/m)?.[1]
      ?.trim();
    if (target === undefined) return false;
    return normalizePath(target).startsWith(normalizePath(path.join(gitDir, 'worktrees')) + path.sep);
  } catch {
    return false;
  }
}

function hasRepoMarkers(dir) {
  return REPO_MARKERS.every((file) => fs.existsSync(path.join(longPath(dir), file)));
}

function isProcessAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err.code === 'EPERM';
  }
}

/**
 * The verify locations (this checkout and the main worktree) with the `<repo>-verify-*` folders next to each.
 * Each group carries the SiblingFolder facts the pure decisions take, plus the folder's `dir`.
 * @returns {{ parent: string, repoName: string, folders: Array<import('../guardrails/src/verify-worktrees.mjs').SiblingFolder & { dir: string }> }[]}
 */
export function verifyFolderGroups({ repo, gitDir }) {
  const [main] = worktreePaths(repo);
  const byPath = new Map();
  for (const repoPath of [repo, main ?? repo]) {
    const abs = path.resolve(repoPath);
    byPath.set(normalizePath(abs), { parent: path.dirname(abs), repoName: path.basename(abs) });
  }
  const registered = new Set(worktreePaths(repo).map(normalizePath));
  return [...byPath.values()].map(({ parent, repoName }) => {
    const prefix = `${repoName}-verify-`;
    const folders = fs
      .readdirSync(parent)
      .filter((name) => name.startsWith(prefix))
      .map((name) => {
        const dir = path.join(parent, name);
        const pid = Number(name.slice(prefix.length));
        return {
          name,
          dir,
          isDirectory: fs.statSync(longPath(dir), { throwIfNoEntry: false })?.isDirectory() ?? false,
          registered: registered.has(normalizePath(dir)),
          linkedToRepo: linkedToRepository(dir, gitDir),
          repoMarker: hasRepoMarkers(dir),
          pidAlive: Number.isInteger(pid) && isProcessAlive(pid)
        };
      });
    return { parent, repoName, folders };
  });
}
