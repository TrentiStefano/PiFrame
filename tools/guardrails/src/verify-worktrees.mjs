/**
 * Which sibling folders left behind by `pnpm run verify` are safe to delete. Pure: no I/O. The script that reads the
 * folders and their git metadata is tools/scripts/verify-ci.mjs.
 *
 * A verify worktree is named `<repo>-verify-<pid>` next to the repository. A folder is selected only when all hold:
 * - its name has that shape for this repository (other names, other repositories and `-verify-` lookalikes are kept);
 * - its pid is not the current run's pid (the current run's folder is never selected);
 * - it is a directory that is a verify worktree of this repository: still registered in git, removed from git but
 *   its `.git` file still points into this repository, or left with no `.git` entry at all (a removal that failed on
 *   long paths deletes the git link first, so the content is all that remains);
 * - its run is not still alive (another verify running now owns its folder).
 */

/**
 * @typedef {object} SiblingFolder
 * @property {string} name folder name, without its parent path
 * @property {boolean} isDirectory
 * @property {boolean} registered the folder is a worktree listed by `git worktree list` of this repository
 * @property {boolean} linkedToRepo its `.git` file points into this repository's `worktrees/` folder
 * @property {boolean} gitEntry the folder has a `.git` entry at all
 * @property {boolean} pidAlive the process that created the folder is still running
 */

/**
 * @param {{ repoName: string, currentPid: number, folders: SiblingFolder[] }} input
 * @returns {string[]} names of the folders to delete, in the order given
 */
export function selectStaleVerifyWorktrees({ repoName, currentPid, folders }) {
  const pattern = new RegExp(`^${escapeRegExp(repoName)}-verify-(\\d+)$`);
  return folders
    .filter((folder) => {
      const match = pattern.exec(folder.name);
      if (!match) return false;
      if (Number(match[1]) === currentPid) return false;
      if (!folder.isDirectory) return false;
      const confirmed = folder.registered || folder.linkedToRepo || !folder.gitEntry;
      if (!confirmed) return false;
      if (folder.pidAlive) return false;
      return true;
    })
    .map((folder) => folder.name);
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * The failure `verify` reports when a verify worktree folder survives its cleanup.
 * @param {{ leftovers: string[] }} input folder paths still on disk
 * @returns {string | null} the message, or null when nothing was left behind
 */
export function leftoverVerifyFailure({ leftovers }) {
  if (leftovers.length === 0) return null;
  const list = leftovers.map((path) => `  - ${path}`).join('\n');
  return (
    `${leftovers.length} verify worktree folder(s) left behind after cleanup:\n${list}\n` +
    'Delete them by hand (on Windows, for example `Remove-Item -LiteralPath "\\\\?\\<path>" -Recurse -Force`), ' +
    'then run verify again.'
  );
}
