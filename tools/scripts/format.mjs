#!/usr/bin/env node
/**
 * Formats the codebase, or checks that it is formatted (--check, used by verify and CI).
 *
 *   pnpm run format                     format Dart and TypeScript/Node files
 *   pnpm run format -- dart             only Dart (dart format, page width from each project's analysis_options.yaml)
 *   pnpm run format -- ts               only TypeScript and Node tooling (Prettier, config in .prettierrc.json)
 *   node tools/scripts/format.mjs --check [dart|ts]
 *
 * Exit code 0 when everything is (or now is) formatted.
 */
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const IS_WIN = process.platform === 'win32';

const FLUTTER_PROJECTS = JSON.parse(readFileSync(path.join(REPO, 'tools/scripts/flutter-projects.json'), 'utf8'));
const DART_DIRS = FLUTTER_PROJECTS.flatMap((p) => [`${p}/lib`, `${p}/test`]);
// TypeScript and Node tooling. Everything else (Markdown, YAML, JSON, the website, the Flutter web glue) is also
// listed in .prettierignore, so an editor or a bare `prettier --write .` leaves it alone too.
const TS_GLOBS = ['apps/agentd', 'packages/pcp-spec', 'packages/pcp-ts', 'test/e2e', 'tools'].map(
  (dir) => `${dir}/**/*.{ts,mts,cts,js,mjs,cjs}`
);

const FORMATTERS = {
  dart: {
    label: 'Dart',
    command: (check) => ({
      cmd: 'dart',
      args: ['format', ...(check ? ['--output=none', '--set-exit-if-changed'] : []), ...DART_DIRS],
      shell: IS_WIN
    })
  },
  ts: {
    label: 'TypeScript/Node',
    command: (check) => ({
      cmd: process.execPath,
      args: [
        path.join(REPO, 'node_modules/prettier/bin/prettier.cjs'),
        check ? '--check' : '--write',
        '--log-level',
        'warn',
        ...TS_GLOBS
      ],
      shell: false
    })
  }
};

const argv = process.argv.slice(2).filter((a) => a !== '--');
const check = argv.includes('--check');
const chosen = argv.filter((a) => a !== '--check');
const unknown = chosen.filter((name) => !FORMATTERS[name]);
if (unknown.length > 0) {
  console.error(
    `Unknown formatter: ${unknown.join(', ')}. Use: ${Object.keys(FORMATTERS).join(', ')} (or nothing for all).`
  );
  process.exit(2);
}

let failed = false;
for (const name of chosen.length > 0 ? chosen : Object.keys(FORMATTERS)) {
  const { label, command } = FORMATTERS[name];
  const { cmd, args, shell } = command(check);
  const result = spawnSync(cmd, args, { cwd: REPO, stdio: 'inherit', shell });
  if (result.status === 0) continue;
  failed = true;
  // Both formatters exit 1 for "files need formatting"; anything else (a syntax error, a missing tool) is a failure to run.
  if (check && result.status === 1) {
    console.error(
      `\n✖ ${label} files are not formatted (listed above). Fix: pnpm run format -- ${name}, then commit the result.\n` +
        `  If the output above says the command was not found instead, install it (see docs/install.md).`
    );
  } else {
    const why = result.error ? result.error.message : `exit code ${result.status}`;
    console.error(`\n✖ ${label} formatter could not run (${why}). Fix the error printed above, then run it again.`);
  }
}
process.exit(failed ? 1 : 0);
