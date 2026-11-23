/**
 * The repository's files as the gate checks see them: tracked plus untracked (not ignored), and only those still on
 * disk, so a file deleted in the working tree counts as gone. Shared by the gate adapters in tools/scripts.
 */
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

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
