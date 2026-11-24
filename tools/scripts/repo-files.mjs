/**
 * The repository's files as the gate checks see them: tracked plus untracked (not ignored), and only those still on
 * disk, so a file deleted in the working tree counts as gone. Shared by the gate adapters in tools/scripts.
 */
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DIAGNOSTICS_BASELINE_PATH } from '../guardrails/src/index.mjs';

/** The repository root. */
export const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

/**
 * @param {string} [repo] the repository root (defaults to this repository)
 * @returns {string[] | null} `/`-separated paths relative to the root, without duplicates, or null when
 *   `git ls-files` fails (not inside a repository)
 */
export function repoFiles(repo = REPO) {
  const listed = spawnSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], {
    cwd: repo,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024
  });
  if (listed.status !== 0) return null;
  return [...new Set(listed.stdout.split('\0').filter(Boolean))].filter((p) => fs.existsSync(path.join(repo, p)));
}

/**
 * Runs a git command in the repository and splits its output into entries (NUL- or newline-separated).
 * A failing command yields no entries, so callers treat it as "nothing to report".
 * @param {...string} args the git arguments
 * @returns {string[]}
 */
export function git(...args) {
  const result = spawnSync('git', args, { cwd: REPO, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  return result.status === 0 ? result.stdout.split(/[\0\n]/).filter(Boolean) : [];
}

/**
 * Files this branch changes (working tree and untracked included) since the diagnostics baseline was last committed.
 * The diagnostics ratchet uses it to name the files a new diagnostic is in.
 * @returns {string[]}
 */
export function changedFiles() {
  const since = git('log', '-1', '--format=%H', '--', DIAGNOSTICS_BASELINE_PATH)[0] ?? 'HEAD';
  return [...git('diff', '--name-only', '-z', since), ...git('ls-files', '-z', '--others', '--exclude-standard')];
}
