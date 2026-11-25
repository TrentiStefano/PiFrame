#!/usr/bin/env node
/**
 * The golden screens: the Flutter widget tests tagged `golden` (apps/pi_frame/test/golden_screens_test.dart) compare
 * five screens, light and dark (ten references), against the references committed in apps/pi_frame/test/goldens/.
 *
 *   node tools/scripts/goldens.mjs            compare (the one verify-only step of the gate, `pnpm run verify`)
 *   node tools/scripts/goldens.mjs --update   regenerate the references (`pnpm run goldens:update`)
 *
 * Windows only: on other platforms it prints why it did not run and exits 0. On Windows the run must execute at least
 * one golden test (goldenRunFailure), so a missing tag cannot pass silently. A mismatch fails the step; its expected,
 * actual and diff images are in apps/pi_frame/test/failures/ (ignored by git, cleared at the next run). See
 * docs/pr-verification.md.
 */
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { countExecutedGoldens, goldenRunFailure } from '../guardrails/src/index.mjs';
import { withChangelog } from './with-changelog.js';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const APP = path.join(REPO, 'apps', 'pi_frame');
const update = process.argv.includes('--update');

if (process.platform !== 'win32') {
  console.log('Golden screens skipped: they are compared on Windows only (docs/pr-verification.md).');
  process.exit(0);
}

/** Runs the golden tests and returns the exit code: the Flutter status, or 1 when no golden test ran. */
function runGoldens(reportFile) {
  const flutter = withChangelog(() =>
    spawnSync(
      'flutter',
      [
        'test',
        '--tags',
        'golden',
        '--reporter',
        'expanded',
        '--file-reporter',
        `json:${reportFile}`,
        ...(update ? ['--update-goldens'] : [])
      ],
      { cwd: APP, stdio: 'inherit', shell: true }
    )
  );
  if (flutter.status !== 0) {
    console.error(
      '\nGolden screens differ from their references. If the change is intended, run: pnpm run goldens:update'
    );
    return flutter.status ?? 1;
  }
  const executed = fs.existsSync(reportFile) ? countExecutedGoldens(fs.readFileSync(reportFile, 'utf8')) : 0;
  const failure = goldenRunFailure({ platform: process.platform, executed });
  if (failure) {
    console.error(`\n${failure}`);
    return 1;
  }
  console.log(`\nGolden screens: ${executed} golden test(s) ran.`);
  return 0;
}

const reportDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-frame-goldens-'));
const code = runGoldens(path.join(reportDir, 'report.json'));
fs.rmSync(reportDir, { recursive: true, force: true });
process.exit(code);
