import test from 'node:test';
import assert from 'node:assert/strict';
import { checkAgentMap } from '../src/index.mjs';

const PATHS = ['AGENTS.md', 'README.md', 'apps/pi_frame/lib/main.dart', 'docs/pr-verification.md', 'docs/adr/0001.md'];
const SCRIPTS = ['check', 'verify', 'pr'];

const map = (...lines) => `${lines.join('\n')}\n`;
const messages = (result) => result.violations.map((v) => v.message);

test('a short map whose paths and scripts all exist passes', () => {
  const text = map(
    '# PiFrame',
    '- `apps/pi_frame/` holds the app; see [the verification guide](docs/pr-verification.md#commands).',
    '- Run `pnpm run check` while working and `pnpm run verify` before a PR (`docs/adr/`, `README.md`).'
  );
  assert.deepEqual(checkAgentMap({ text, paths: PATHS, scripts: SCRIPTS }), { ok: true, violations: [] });
});

test('a map over 100 lines fails and says how long it is', () => {
  const lines = Array.from({ length: 101 }, (_, i) => `line ${i + 1}`);
  const result = checkAgentMap({ text: map(...lines), paths: PATHS, scripts: SCRIPTS });
  assert.equal(result.ok, false);
  assert.deepEqual(messages(result), [
    'AGENTS.md has 101 lines, over the limit of 100. Keep it a map: move detail into a doc and point at it.'
  ]);
});

test('exactly 100 lines passes, and the final newline does not count as a line (CRLF included)', () => {
  const lines = Array.from({ length: 100 }, (_, i) => `line ${i + 1}`);
  assert.equal(checkAgentMap({ text: map(...lines).replace(/\n/g, '\r\n'), paths: PATHS, scripts: SCRIPTS }).ok, true);
});

test('a mentioned path that is not tracked fails, naming the line and the path', () => {
  const text = map(
    '# PiFrame',
    'Real captures: `scratch/release_ui_screenshots/*.png` and [notes](docs/missing.md).',
    'The app lives in `apps/pi_frame/` and its entry point in `apps/pi_frame/lib/main.dart`.'
  );
  const result = checkAgentMap({ text, paths: PATHS, scripts: SCRIPTS });
  assert.equal(result.ok, false);
  assert.deepEqual(result.violations, [
    {
      line: 2,
      message:
        'AGENTS.md:2 names `scratch/release_ui_screenshots/*.png`, which matches no tracked file or folder. Fix the path or remove the mention.'
    },
    {
      line: 2,
      message:
        'AGENTS.md:2 names `docs/missing.md`, which matches no tracked file or folder. Fix the path or remove the mention.'
    }
  ]);
});

test('a bare file name is a path from the repository root', () => {
  const result = checkAgentMap({ text: map('See `README.md` and `ci.yml`.'), paths: PATHS, scripts: SCRIPTS });
  assert.deepEqual(messages(result), [
    'AGENTS.md:1 names `ci.yml`, which matches no tracked file or folder. Fix the path or remove the mention.'
  ]);
});

test('globs match tracked files; URLs, home paths, placeholders, package names and versions are not paths', () => {
  const text = map(
    'Captures: `docs/adr/*.md`, `apps/**/main.dart`. Sessions in `~/.pi/agent/sessions`, on `127.0.0.1`.',
    'Tests: `<package>/src/**/*.test.ts`; packages `@piframe/agentd`; see https://example.com/a/b.md and',
    '[the site](https://example.com/x.md), the [commands](#commands) section, and `node --test` with `-- --e2e`.'
  );
  assert.deepEqual(checkAgentMap({ text, paths: PATHS, scripts: SCRIPTS }), { ok: true, violations: [] });
});

test('paths inside a fenced code block are checked too', () => {
  const text = map('```bash', 'node tools/scripts/gone.mjs', '```');
  assert.deepEqual(messages(checkAgentMap({ text, paths: PATHS, scripts: SCRIPTS })), [
    'AGENTS.md:2 names `tools/scripts/gone.mjs`, which matches no tracked file or folder. Fix the path or remove the mention.'
  ]);
});

test('`pnpm run <script>` without that root package.json script fails', () => {
  const text = map(
    '| check | `pnpm run check` |',
    '| harness | `pnpm run harness -- --help`, then `pnpm run check -- tools/guardrails` |',
    'Formatting: pnpm run format:check.'
  );
  const result = checkAgentMap({ text, paths: [...PATHS, 'tools/guardrails/x.mjs'], scripts: SCRIPTS });
  assert.equal(result.ok, false);
  assert.deepEqual(messages(result), [
    'AGENTS.md:2 runs `pnpm run harness`, but the root package.json has no "harness" script. Fix the command or add the script.',
    'AGENTS.md:3 runs `pnpm run format:check`, but the root package.json has no "format:check" script. Fix the command or add the script.'
  ]);
});

test('a glob without a folder is a file-name pattern that matches anywhere', () => {
  const text = map('Dart tests are `*_test.dart`; scripts are `*.mjs`.');
  assert.deepEqual(
    messages(checkAgentMap({ text, paths: [...PATHS, 'apps/pi_frame/test/a_test.dart'], scripts: SCRIPTS })),
    ['AGENTS.md:1 names `*.mjs`, which matches no tracked file or folder. Fix the path or remove the mention.']
  );
});
