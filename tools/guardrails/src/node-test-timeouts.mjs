/**
 * Node test timeouts: every `node --test` command passes `--test-timeout`. Without it, a test that leaks a handle
 * (an open timer, server or child process) keeps Node alive and hangs the run instead of failing it (#115). Covers the
 * package `scripts` and the gate's own commands; each command of an `&&` / `;` chain is checked on its own.
 *
 * Pure: no I/O. tools/scripts/check-node-test-timeouts.mjs collects the commands and calls it. See
 * docs/pr-verification.md ("Node test timeouts").
 */

/** The per-test limit the gate's own `node --test` commands use. */
export const NODE_TEST_TIMEOUT_MS = 120_000;

const NODE_TEST = /\bnode\s+(?:\S+\s+)*?--test\b/;

/**
 * @param {{ commands: { path: string, name: string, command: string }[] }} input
 * @returns {{ ok: boolean, problems: { path: string, name: string, message: string }[] }}
 */
export function checkNodeTestTimeouts({ commands }) {
  const problems = [];
  for (const { path, name, command } of commands) {
    for (const part of command.split(/&&|;|\|\|/)) {
      const segment = part.trim();
      if (NODE_TEST.test(segment) && !/--test-timeout\b/.test(segment)) {
        problems.push({
          path,
          name,
          message: `\`${segment}\` has no --test-timeout: a test that leaks a handle would hang the run.`
        });
      }
    }
  }
  return { ok: problems.length === 0, problems };
}
