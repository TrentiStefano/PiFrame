/**
 * Argument helpers for open-pr.mjs. Kept separate so they can be unit tested without running the script.
 */

export const VERIFY_FLAGS = new Set(['--release', '--e2e', '--force', '--no-merge', '--verbose', '--keep']);

/**
 * Splits argv into flags for `verify` and everything else, which is forwarded to `gh pr create`.
 * A bare `--` is dropped first: `pnpm run pr -- --title ...` makes pnpm pass the separator on to this
 * script, and gh would read it as the start of positional arguments.
 */
export function splitArgs(argv) {
  const args = argv.filter((a) => a !== '--');
  return {
    verifyArgs: args.filter((a) => VERIFY_FLAGS.has(a)),
    ghArgs: args.filter((a) => !VERIFY_FLAGS.has(a))
  };
}

/**
 * Full argument list for `gh pr create`. The body is always given (see prBodyText), so gh never fills it from the
 * commits: the PR template is the only source of the review shape.
 */
export function buildPrCreateArgs(ghArgs) {
  return ['pr', 'create', '--base', 'main', ...ghArgs];
}

/**
 * The pull request body the arguments give: the text of `--body`, or of the `--body-file` (read with `readFile`,
 * which gets the path as written, `-` included). Undefined when neither flag is given.
 */
export function prBodyText(ghArgs, readFile) {
  for (let i = 0; i < ghArgs.length; i += 1) {
    const arg = ghArgs[i];
    if (arg === '--body') return ghArgs[i + 1] ?? '';
    if (arg.startsWith('--body=')) return arg.slice('--body='.length);
    if (arg === '--body-file') return readFile(ghArgs[i + 1] ?? '');
    if (arg.startsWith('--body-file=')) return readFile(arg.slice('--body-file='.length));
  }
  return undefined;
}
