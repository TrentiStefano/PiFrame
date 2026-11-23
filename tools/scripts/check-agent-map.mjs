#!/usr/bin/env node
/**
 * The agent map check (`check`, `verify` and CI run it). Reads AGENTS.md, the repository's files (tracked plus
 * untracked, not ignored, as they are on disk) and the root package.json scripts, and fails when AGENTS.md is over
 * 100 lines, names a path that does not exist, or runs a `pnpm run <script>` the root package.json lacks.
 * The decision logic lives in tools/guardrails/src/agent-map.mjs.
 *
 *   node tools/scripts/check-agent-map.mjs
 */
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { AGENT_MAP_PATH, checkAgentMap } from '../guardrails/src/index.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

const listed = spawnSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], {
  cwd: REPO,
  encoding: 'utf8',
  maxBuffer: 64 * 1024 * 1024
});
if (listed.status !== 0) {
  console.error('✖ agent map check: `git ls-files` failed; run it inside the repository.');
  process.exit(1);
}
const paths = listed.stdout.split('\0').filter((p) => p && fs.existsSync(path.join(REPO, p)));
const text = fs.readFileSync(path.join(REPO, AGENT_MAP_PATH), 'utf8');
const scripts = Object.keys(JSON.parse(fs.readFileSync(path.join(REPO, 'package.json'), 'utf8')).scripts ?? {});

const { ok, violations } = checkAgentMap({ text, paths, scripts });
if (ok) {
  console.log(`✔ agent map check: ${AGENT_MAP_PATH} is short and every path and script it names exists.`);
} else {
  console.error(`\n✖ agent map check: ${violations.length} problem(s) in ${AGENT_MAP_PATH}:\n`);
  for (const v of violations) console.error(`- ${v.message}`);
  process.exit(1);
}
