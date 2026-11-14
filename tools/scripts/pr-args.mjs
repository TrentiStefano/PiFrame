/**
 * Argument helpers for open-pr.mjs. Kept separate so they can be unit tested without running the script.
 */

export const VERIFY_FLAGS = new Set(['--release', '--e2e', '--force', '--no-merge', '--verbose', '--keep']);

/** Splits argv into flags for `verify` and everything else, which is forwarded to `gh pr create`. */
export function splitArgs(argv) {
  return {
    verifyArgs: argv.filter((a) => VERIFY_FLAGS.has(a)),
    ghArgs: argv.filter((a) => !VERIFY_FLAGS.has(a))
  };
}

/** Full argument list for `gh pr create`. Without --title/--body/--fill/--body-file, the commits fill the PR. */
export function buildPrCreateArgs(ghArgs) {
  const hasContent = ghArgs.includes('--title') || ghArgs.includes('--body') || ghArgs.includes('--fill') || ghArgs.includes('--body-file');
  return ['pr', 'create', '--base', 'main', ...(hasContent ? [] : ['--fill']), ...ghArgs];
}
