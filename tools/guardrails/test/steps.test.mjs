import test from 'node:test';
import assert from 'node:assert/strict';
import { stepList } from '../src/index.mjs';

const commandLines = (steps) => steps.map((s) => s.command.join(' '));

test('verify runs the full gate in order, including codegen parity and an explicit TS lint after the build', () => {
  assert.deepEqual(commandLines(stepList('verify')), [
    'pnpm install --frozen-lockfile',
    'node tools/recon/verify.ts',
    'pnpm --filter @piframe/pcp-spec run test',
    'pnpm -r run build',
    'pnpm -r run lint',
    'node tools/codegen/generate.js',
    'pnpm -r run test',
    'pnpm run check:notices',
    'pnpm run check:version',
    'pnpm run check:agentd-bundle',
    'pnpm run smoke:agentd-bundle',
    'node --test tools/scripts/test-windows-release-name.test.mjs',
    'node tools/scripts/setup-flutter.js',
    'node tools/scripts/lint-flutter.js',
    'node tools/scripts/test-flutter.js'
  ]);
});

const WEB_BUILD = 'flutter build web --release --no-web-resources-cdn --pwa-strategy=none --dart-define=PI_FRAME_VERSION=1.5.1';
const tailOf = (steps, n) => steps.slice(-n).map((s) => ({ command: s.command.join(' '), cwd: s.cwd }));

test('verify --release appends the web and desktop release builds for the given platform and version', () => {
  const steps = stepList('verify', { release: true, platform: 'windows', appVersion: '1.5.1' });
  assert.equal(steps.length, stepList('verify').length + 2);
  assert.deepEqual(tailOf(steps, 2), [
    { command: WEB_BUILD, cwd: 'apps/pi_frame' },
    {
      command: 'flutter build windows --release --build-name 1.5.1 --build-number 1 --dart-define=PI_FRAME_VERSION=1.5.1',
      cwd: 'apps/pi_frame'
    }
  ]);
});

test('verify --e2e builds the web app, then runs the emulated-iPhone test', () => {
  const steps = stepList('verify', { e2e: true, platform: 'linux', appVersion: '1.5.1' });
  assert.equal(steps.length, stepList('verify').length + 2);
  assert.deepEqual(tailOf(steps, 2), [
    { command: WEB_BUILD, cwd: 'apps/pi_frame' },
    { command: 'node tools/remote-e2e/remote-iphone-e2e.mjs', cwd: undefined }
  ]);
});

test('verify --release --e2e builds the web app once, then desktop, then the e2e test', () => {
  const steps = stepList('verify', { release: true, e2e: true, platform: 'macos', appVersion: '2.0.0' });
  assert.deepEqual(
    steps.slice(-3).map((s) => s.command.slice(0, 3).join(' ')),
    ['flutter build web', 'flutter build macos', 'node tools/remote-e2e/remote-iphone-e2e.mjs']
  );
});

test('ci runs exactly the verify gate, split into the node and flutter jobs', () => {
  const ci = stepList('ci');
  assert.deepEqual(commandLines(ci), commandLines(stepList('verify')));
  const byJob = (job) => commandLines(ci.filter((s) => s.job === job));
  assert.deepEqual(byJob('flutter'), [
    'node tools/scripts/setup-flutter.js',
    'node tools/scripts/lint-flutter.js',
    'node tools/scripts/test-flutter.js'
  ]);
  assert.equal(byJob('node').length + byJob('flutter').length, ci.length);
});

test('an unknown tier is an error that names the known tiers', () => {
  assert.throws(() => stepList('everything'), /verify.*ci/);
});

test('a release build without a platform or version is refused instead of building garbage', () => {
  assert.throws(() => stepList('verify', { release: true, appVersion: '1.5.1' }), /platform/);
  assert.throws(() => stepList('verify', { e2e: true, platform: 'linux' }), /appVersion/);
});
