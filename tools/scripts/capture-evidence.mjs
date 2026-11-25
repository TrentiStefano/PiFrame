#!/usr/bin/env node
/**
 * Refreshes the tracked captures on purpose: the design evidence (docs/design-evidence) and the website UI captures
 * (website/assets/img/ui). Plain `flutter test` never writes them; the capture tests write to a temporary folder unless
 * the flags below are set, and this script sets them for all four capture tests:
 *
 *   redesign_layout_test.dart           PI_FRAME_CAPTURE_EVIDENCE=1 (light, then dark with PI_FRAME_CAPTURE_DARK=1)
 *   capture_website_evidence_test.dart  PI_FRAME_CAPTURE_EVIDENCE=1
 *   context_policy_panel_test.dart      PIFRAME_CAPTURE_CONTEXT_POLICY=1
 *   question_preview_capture_test.dart  PIFRAME_CAPTURE_QUESTION=1
 *
 *   pnpm run capture:evidence
 *
 * Review the result with `git status` and commit only the captures you meant to change.
 */
import { spawnSync } from 'node:child_process';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { withChangelog } from './with-changelog.js';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const FLUTTER_APP = path.join(REPO, 'apps', 'pi_frame');
const IS_WIN = process.platform === 'win32';

const CAPTURE_FLAGS = {
  PI_FRAME_CAPTURE_EVIDENCE: '1',
  PIFRAME_CAPTURE_CONTEXT_POLICY: '1',
  PIFRAME_CAPTURE_QUESTION: '1'
};

const RUNS = [
  {
    label: 'capture tests, light theme',
    env: CAPTURE_FLAGS,
    tests: [
      'test/redesign_layout_test.dart',
      'test/capture_website_evidence_test.dart',
      'test/context_policy_panel_test.dart',
      'test/question_preview_capture_test.dart'
    ]
  },
  {
    label: 'redesign captures, dark theme',
    env: { ...CAPTURE_FLAGS, PI_FRAME_CAPTURE_DARK: '1' },
    tests: ['test/redesign_layout_test.dart']
  }
];

// The in-app changelog is generated before any Flutter test (tools/scripts/with-changelog.js).
withChangelog(() => {
  for (const run of RUNS) {
    console.log(`\nRunning ${run.label} ...`);
    const result = spawnSync('flutter', ['test', ...run.tests], {
      cwd: FLUTTER_APP,
      stdio: 'inherit',
      shell: IS_WIN,
      env: { ...process.env, ...run.env }
    });
    if (result.status !== 0) {
      console.error(`\nCapture failed: ${run.label}. The tracked captures may be partly refreshed; check git status.`);
      process.exit(result.status || 1);
    }
  }
});
console.log('\nTracked captures refreshed. Review them with git status before committing.');
