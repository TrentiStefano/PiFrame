#!/usr/bin/env node
/**
 * The golden screens: the Flutter widget tests tagged `golden` (apps/pi_frame/test/golden_screens_test.dart) compare
 * four screens, light and dark, against the references committed in apps/pi_frame/test/goldens/.
 *
 *   node tools/scripts/goldens.mjs            compare (the one verify-only step of the gate, `pnpm run verify`)
 *   node tools/scripts/goldens.mjs --update   regenerate the references (`pnpm run goldens:update`)
 *
 * Windows only: on other platforms it prints why it did not run and exits 0. A mismatch fails the step; its expected,
 * actual and diff images are in apps/pi_frame/test/failures/ (ignored by git, cleared at the next run). See
 * docs/pr-verification.md.
 */
import { spawnSync } from 'node:child_process';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const APP = path.join(REPO, 'apps', 'pi_frame');
const update = process.argv.includes('--update');

if (process.platform !== 'win32') {
  console.log('Golden screens skipped: they are compared on Windows only (docs/pr-verification.md).');
  process.exit(0);
}

// The app bundles the in-app changelog, which flutter test needs (as in test-flutter.js).
const sync = spawnSync(process.execPath, [path.join(REPO, 'tools', 'scripts', 'sync-changelog.mjs')], {
  stdio: 'inherit'
});
if (sync.status !== 0) {
  console.error('Failed to generate apps/pi_frame/assets/CHANGELOG.md');
  process.exit(sync.status || 1);
}

const args = ['test', '--tags', 'golden', ...(update ? ['--update-goldens'] : [])];
const res = spawnSync('flutter', args, { cwd: APP, stdio: 'inherit', shell: true });
if (res.status !== 0) {
  console.error(
    '\nGolden screens differ from their references. If the change is intended, run: pnpm run goldens:update'
  );
}
process.exit(res.status ?? 1);
