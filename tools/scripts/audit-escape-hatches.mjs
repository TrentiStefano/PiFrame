#!/usr/bin/env node
/**
 * The escape-hatch ratchet (`check`, `verify` and CI run it). Reads the repository's files (tracked plus untracked,
 * not ignored, as they are on disk) and the committed baseline, and fails when any count differs from it.
 * The decision logic lives in tools/guardrails/src/escape-hatches.mjs. See docs/pr-verification.md.
 *
 *   node tools/scripts/audit-escape-hatches.mjs
 */
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { auditEscapeHatches, BASELINE_PATH } from '../guardrails/src/index.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const SOURCE = /\.(dart|ts|tsx|mts|cts|js|jsx|mjs|cjs)$/;

function git(...args) {
  const result = spawnSync('git', args, { cwd: REPO, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  return result.status === 0
    ? result.stdout
        .split('\0')
        .flatMap((s) => s.split('\n'))
        .filter(Boolean)
    : null;
}

const listed = git('ls-files', '-z', '--cached', '--others', '--exclude-standard');
if (!listed) {
  console.error('✖ escape-hatch audit: `git ls-files` failed; run it inside the repository.');
  process.exit(1);
}
const files = [...new Set(listed)]
  .filter((p) => SOURCE.test(p) && fs.existsSync(path.join(REPO, p)))
  .map((p) => ({ path: p, contents: fs.readFileSync(path.join(REPO, p), 'utf8') }));

// Files changed on this branch (against origin/main, when it is known) and in the working tree: listed first.
const base = git('merge-base', 'HEAD', 'origin/main')?.[0];
const changedPaths = [
  ...(base ? (git('diff', '--name-only', '-z', base, 'HEAD') ?? []) : []),
  ...(git('diff', '--name-only', '-z', 'HEAD') ?? []),
  ...(git('ls-files', '-z', '--others', '--exclude-standard') ?? [])
];

const baseline = JSON.parse(fs.readFileSync(path.join(REPO, BASELINE_PATH), 'utf8'));
const { ok, counts, mismatches } = auditEscapeHatches({ files, baseline, changedPaths });

const totals = Object.entries(counts).map(([pkg, kinds]) => {
  const sum = (kind) => Object.values(kinds[kind]).reduce((a, b) => a + b, 0);
  return `${pkg} ${sum('lib')}/${sum('test')}`;
});
console.log(`Escape hatches per package (lib/test): ${totals.join(', ')}`);

if (ok) {
  console.log(`✔ escape-hatch audit: every count matches ${BASELINE_PATH}.`);
} else {
  console.error(`\n✖ escape-hatch audit: ${mismatches.length} count(s) differ from ${BASELINE_PATH}:\n`);
  for (const m of mismatches) console.error(`- ${m.message}\n`);
  process.exit(1);
}
