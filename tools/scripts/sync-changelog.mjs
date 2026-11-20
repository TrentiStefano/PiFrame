// Generates the in-app changelog (apps/pi_frame/assets/CHANGELOG.md, not committed) from the root CHANGELOG.md.
// Run by `pnpm run setup` (through setup-flutter.js), `pnpm run run:app*` and the release workflow before Flutter
// builds. `--check` only reports drift (exit 1) and never writes; the version check uses that mode.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { syncChangelog, CHANGELOG_ASSET } from '../guardrails/src/index.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

/** Reads both changelogs and applies the guardrails decision. Returns the sync result. */
export function runChangelogSync(mode) {
  const assetPath = path.join(repoRoot, CHANGELOG_ASSET);
  const root = readFileSync(path.join(repoRoot, 'CHANGELOG.md'), 'utf8');
  const asset = existsSync(assetPath) ? readFileSync(assetPath, 'utf8') : null;
  const result = syncChangelog({ root, asset, mode });
  if (result.status === 'write') writeFileSync(assetPath, result.content, 'utf8');
  return result;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = runChangelogSync(process.argv.includes('--check') ? 'check' : 'write');
  if (result.status === 'fail') {
    console.error(result.message);
    process.exit(1);
  }
  console.log(result.message);
}
