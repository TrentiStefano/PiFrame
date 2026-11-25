/**
 * Whether a golden screens run actually executed its golden tests. Pure: no I/O. tools/scripts/goldens.mjs runs
 * `flutter test --tags golden` with a JSON file reporter and asks these functions for the verdict, so an empty run
 * (for example a tag that no test carries) can never pass the gate silently.
 */

/** Golden tests are named `golden: <screen> (<theme>)` in apps/pi_frame/test/golden_screens_test.dart. */
const GOLDEN_NAME = /^golden: /;

/**
 * Counts the golden tests that passed, from a `flutter test --file-reporter json` report (one JSON event per line).
 * @param {string} report the report text
 * @returns {number}
 */
export function countExecutedGoldens(report) {
  const names = new Map();
  let executed = 0;
  for (const line of report.split(/\r?\n/)) {
    if (line.trim() === '') continue;
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      continue;
    }
    if (event.type === 'testStart' && event.test) {
      names.set(event.test.id, event.test.name ?? '');
    } else if (event.type === 'testDone' && event.result === 'success' && !event.skipped) {
      if (GOLDEN_NAME.test(names.get(event.testID) ?? '')) executed += 1;
    }
  }
  return executed;
}

/**
 * On Windows the golden screens must run: zero executed golden tests fails the step. Elsewhere the step is skipped
 * by design (goldens.mjs prints that and exits before running Flutter), so no count is expected.
 * @param {{ platform: string, executed: number }} input
 * @returns {string | null} the message, or null when the run is acceptable
 */
export function goldenRunFailure({ platform, executed }) {
  if (platform !== 'win32') return null;
  if (executed > 0) return null;
  return (
    'No golden test ran on Windows. The golden tests carry the `golden` tag (apps/pi_frame/dart_test.yaml declares it); ' +
    'a missing tag or a renamed test would otherwise pass without comparing any screen.'
  );
}
