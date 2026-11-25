/**
 * The app bundles its in-app changelog (apps/pi_frame/assets/CHANGELOG.md), generated from the root CHANGELOG.md and
 * not committed. Every Flutter run in the gate needs it, so the scripts that run Flutter generate it first, here.
 */
const { spawnSync } = require('child_process');
const path = require('path');

const SYNC_SCRIPT = path.join(__dirname, 'sync-changelog.mjs');

/**
 * Generates the changelog, then runs `run`. Exits the process when the generation fails, so no Flutter run starts
 * against a missing or stale copy.
 * @template T
 * @param {() => T} run
 * @returns {T}
 */
function withChangelog(run) {
  const sync = spawnSync(process.execPath, [SYNC_SCRIPT], { stdio: 'inherit' });
  if (sync.status !== 0) {
    console.error('Failed to generate apps/pi_frame/assets/CHANGELOG.md');
    process.exit(sync.status || 1);
  }
  return run();
}

module.exports = { withChangelog };
