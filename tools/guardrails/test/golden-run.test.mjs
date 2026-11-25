import test from 'node:test';
import assert from 'node:assert/strict';
import { countExecutedGoldens, goldenRunFailure } from '../src/index.mjs';

/** A `flutter test --file-reporter json` report: one JSON event per line. */
const report = (...events) => events.map((event) => JSON.stringify(event)).join('\n');
const start = (id, name) => ({ type: 'testStart', test: { id, name } });
const done = (testID, result, skipped = false) => ({ type: 'testDone', testID, result, skipped, hidden: false });

test('counts the golden tests that passed', () => {
  const text = report(
    start(1, 'golden: welcome (light)'),
    done(1, 'success'),
    start(2, 'golden: welcome (dark)'),
    done(2, 'success')
  );
  assert.equal(countExecutedGoldens(text), 2);
});

test('a golden test that failed or was skipped is not counted as executed', () => {
  const text = report(
    start(1, 'golden: welcome (light)'),
    done(1, 'failure'),
    start(2, 'golden: workspace (light)'),
    done(2, 'success', true)
  );
  assert.equal(countExecutedGoldens(text), 0);
});

test('other tests are not golden tests', () => {
  const text = report(start(1, 'Composer sends on enter'), done(1, 'success'));
  assert.equal(countExecutedGoldens(text), 0);
});

test('blank and non-JSON lines are ignored', () => {
  const text = `\n${report(start(1, 'golden: settings (dark)'), done(1, 'success'))}\nthis is not json\n`;
  assert.equal(countExecutedGoldens(text), 1);
});

test('no golden test ran on Windows is a failure that says why', () => {
  const message = goldenRunFailure({ platform: 'win32', executed: 0 });
  assert.match(message, /No golden test ran/);
  assert.match(message, /`golden` tag/);
});

test('golden tests ran on Windows gives no failure', () => {
  assert.equal(goldenRunFailure({ platform: 'win32', executed: 10 }), null);
});

test('off Windows the golden step is skipped by design, so zero is not a failure', () => {
  assert.equal(goldenRunFailure({ platform: 'linux', executed: 0 }), null);
});
