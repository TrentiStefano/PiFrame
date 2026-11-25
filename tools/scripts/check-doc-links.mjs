#!/usr/bin/env node
/**
 * The doc link check (`check`, `verify` and CI run it). Reads the repository's files and fails on any broken relative
 * link (missing file or heading anchor) in docs/, every README.md and the root agent context (AGENTS.md,
 * GLOSSARY.md, DESIGN.md). The decision logic lives in tools/guardrails/src/doc-links.mjs. See
 * docs/pr-verification.md.
 *
 *   node tools/scripts/check-doc-links.mjs
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { checkDocLinks } from '../guardrails/src/index.mjs';
import { REPO, repoFiles } from './repo-files.mjs';

const trackedFiles = repoFiles();
if (!trackedFiles) {
  console.error('✖ doc link check: `git ls-files` failed; run it inside the repository.');
  process.exit(1);
}
const files = trackedFiles
  .filter((p) => /\.md$/i.test(p))
  .map((p) => ({ path: p, contents: fs.readFileSync(path.join(REPO, p), 'utf8') }));

const { ok, problems } = checkDocLinks({ files, trackedFiles });
if (ok) {
  console.log(
    '✔ doc link check: every relative link in docs/, the README files and the root agent context (AGENTS.md, GLOSSARY.md, DESIGN.md) resolves.'
  );
} else {
  console.error(`\n✖ doc link check: ${problems.length} broken link(s):\n`);
  for (const p of problems) console.error(`- ${p.message}\n`);
  process.exit(1);
}
