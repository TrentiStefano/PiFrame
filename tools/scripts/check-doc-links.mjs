#!/usr/bin/env node
/**
 * The doc link check (`check`, `verify` and CI run it). Reads the tracked files and fails on any broken relative
 * link (missing file or heading anchor) in docs/, the README files and AGENTS.md.
 * The decision logic lives in tools/guardrails/src/doc-links.mjs. See docs/pr-verification.md.
 *
 *   node tools/scripts/check-doc-links.mjs
 */
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkDocLinks } from '../guardrails/src/index.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

const listed = spawnSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], {
  cwd: REPO,
  encoding: 'utf8',
  maxBuffer: 64 * 1024 * 1024
});
if (listed.status !== 0) {
  console.error('✖ doc link check: `git ls-files` failed; run it inside the repository.');
  process.exit(1);
}
// Tracked plus untracked (not ignored) files that are on disk: a file deleted in the working tree counts as gone.
const trackedFiles = [...new Set(listed.stdout.split('\0').filter(Boolean))].filter((p) =>
  fs.existsSync(path.join(REPO, p))
);
const files = trackedFiles
  .filter((p) => /\.md$/i.test(p))
  .map((p) => ({ path: p, contents: fs.readFileSync(path.join(REPO, p), 'utf8') }));

const { ok, broken } = checkDocLinks({ files, trackedFiles });
if (ok) {
  console.log('✔ doc link check: every relative link in docs/, the README files and AGENTS.md resolves.');
} else {
  console.error(`\n✖ doc link check: ${broken.length} broken link(s):\n`);
  for (const b of broken) console.error(`- ${b.message}\n`);
  process.exit(1);
}
