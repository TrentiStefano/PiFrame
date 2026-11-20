/**
 * The in-app changelog (apps/pi_frame/assets/CHANGELOG.md) is a generated, untracked copy of the root CHANGELOG.md.
 * Flutter setup writes it (`write` mode); the version check in verify and CI only checks it (`check` mode).
 *
 * Pure: no I/O. The caller reads both files and, for a `write` result, writes `content` to the asset.
 */

export const CHANGELOG_ASSET = 'apps/pi_frame/assets/CHANGELOG.md';
export const CHANGELOG_FIX_COMMAND = 'node tools/scripts/sync-changelog.mjs';

/**
 * @typedef {object} ChangelogSyncInput
 * @property {string} root contents of the root CHANGELOG.md
 * @property {string | null} asset contents of the in-app copy, or null when it does not exist
 * @property {'write' | 'check'} mode
 */

/**
 * @typedef {{ status: 'ok', message: string }
 *   | { status: 'write', content: string, message: string }
 *   | { status: 'fail', message: string }} ChangelogSyncResult
 */

/**
 * @param {ChangelogSyncInput} input
 * @returns {ChangelogSyncResult}
 */
export function syncChangelog({ root, asset, mode }) {
  if (mode !== 'write' && mode !== 'check')
    throw new Error(`syncChangelog: unknown mode "${mode}". Known modes: write, check.`);
  if (typeof root !== 'string') throw new Error('syncChangelog: the root CHANGELOG.md contents are required.');
  if (asset === root) return { status: 'ok', message: `${CHANGELOG_ASSET} matches CHANGELOG.md.` };
  if (mode === 'write')
    return { status: 'write', content: root, message: `Generated ${CHANGELOG_ASSET} from CHANGELOG.md.` };
  const problem = asset === null ? 'is missing' : 'is stale (it differs from CHANGELOG.md)';
  return {
    status: 'fail',
    message:
      `${CHANGELOG_ASSET} ${problem}. It is generated from the root CHANGELOG.md and not committed; ` +
      `regenerate it with \`${CHANGELOG_FIX_COMMAND}\` (\`pnpm run setup\` also does).`
  };
}
