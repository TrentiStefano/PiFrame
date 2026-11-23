#!/usr/bin/env node
/**
 * The agent map check (`check`, `verify` and CI run it). Reads AGENTS.md, the repository's files (tracked plus
 * untracked, not ignored, as they are on disk) and the root package.json scripts, and fails when AGENTS.md is over
 * 100 lines, names a path that does not exist, or runs a `pnpm run <script>` the root package.json lacks.
 * The decision logic lives in tools/guardrails/src/agent-map.mjs.
 *
 *   node tools/scripts/check-agent-map.mjs
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { AGENT_MAP_PATH, checkAgentMap } from '../guardrails/src/index.mjs';
import { REPO, repoFiles } from './repo-files.mjs';

const paths = repoFiles();
if (!paths) {
  console.error('✖ agent map check: `git ls-files` failed; run it inside the repository.');
  process.exit(1);
}
const text = fs.readFileSync(path.join(REPO, AGENT_MAP_PATH), 'utf8');
const scripts = Object.keys(JSON.parse(fs.readFileSync(path.join(REPO, 'package.json'), 'utf8')).scripts ?? {});

const { ok, problems } = checkAgentMap({ text, paths, scripts });
if (ok) {
  console.log(`✔ agent map check: ${AGENT_MAP_PATH} is short and every path and script it names exists.`);
} else {
  console.error(`\n✖ agent map check: ${problems.length} problem(s) in ${AGENT_MAP_PATH}:\n`);
  for (const p of problems) console.error(`- ${p.message}`);
  process.exit(1);
}
