import test from 'node:test';
import assert from 'node:assert/strict';
import { stepList } from '../src/index.mjs';

const commandLines = (steps) => steps.map((s) => s.command.join(' '));

test('verify runs the full gate in order, including codegen parity and an explicit TS lint after the build', () => {
  assert.deepEqual(commandLines(stepList('verify')), [
    'pnpm install --frozen-lockfile',
    'node tools/scripts/format.mjs --check ts',
    'node tools/scripts/audit-escape-hatches.mjs',
    'node tools/scripts/lint-design.mjs',
    'node tools/scripts/check-design-tokens.mjs',
    'node tools/recon/verify.ts',
    'pnpm --filter @piframe/pcp-spec run test',
    'pnpm -r run build',
    'pnpm -r run lint',
    'node tools/codegen/generate.js',
    'pnpm -r run test',
    'pnpm run check:notices',
    'pnpm run check:agentd-bundle',
    'pnpm run smoke:agentd-bundle',
    'node --test tools/scripts/test-windows-release-name.test.mjs',
    'node tools/scripts/setup-flutter.js',
    'node tools/scripts/check-version-sync.mjs',
    'node tools/scripts/format.mjs --check dart',
    'node tools/scripts/lint-flutter.js',
    'node tools/scripts/test-flutter.js'
  ]);
});

const WEB_BUILD =
  'flutter build web --release --no-web-resources-cdn --pwa-strategy=none --dart-define=PI_FRAME_VERSION=1.5.1';
const tailOf = (steps, n) => steps.slice(-n).map((s) => ({ command: s.command.join(' '), cwd: s.cwd }));

test('verify --release appends the web and desktop release builds for the given platform and version', () => {
  const steps = stepList('verify', { release: true, platform: 'windows', appVersion: '1.5.1' });
  assert.equal(steps.length, stepList('verify').length + 2);
  assert.deepEqual(tailOf(steps, 2), [
    { command: WEB_BUILD, cwd: 'apps/pi_frame' },
    {
      command:
        'flutter build windows --release --build-name 1.5.1 --build-number 1 --dart-define=PI_FRAME_VERSION=1.5.1',
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
    'node tools/scripts/check-version-sync.mjs',
    'node tools/scripts/format.mjs --check dart',
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

const FLUTTER_PROJECTS = ['packages/pi_frame_protocol', 'packages/pi_frame_theme', 'apps/pi_frame'];
const check = (tests = []) => stepList('check', { tests, flutterProjects: FLUTTER_PROJECTS });

test('check is the inner loop: escape-hatch audit, DESIGN.md lint and token match, build (for the workspace type declarations), type checking and flutter analyze', () => {
  assert.deepEqual(commandLines(check()), [
    'node tools/scripts/audit-escape-hatches.mjs',
    'node tools/scripts/lint-design.mjs',
    'node tools/scripts/check-design-tokens.mjs',
    'pnpm -r run build',
    'pnpm -r run lint',
    // The app's pubspec lists the untracked in-app changelog: analyze and the Flutter tests both need it.
    'node tools/scripts/sync-changelog.mjs',
    'node tools/scripts/lint-flutter.js'
  ]);
});

const ANALYSIS_STEPS = 7;

test('check never installs, creates a worktree or merges', () => {
  const steps = check(['apps/pi_frame/test/a_test.dart', 'tools/guardrails/test/steps.test.mjs']);
  for (const line of commandLines(steps)) {
    assert.doesNotMatch(line, /\binstall\b|\bworktree\b|\bmerge\b|setup-flutter|pub get/, line);
  }
});

const withCwd = (steps) => steps.map((s) => ({ command: s.command.join(' '), cwd: s.cwd }));

test('check runs a Dart test file with flutter test inside its project, after analysis', () => {
  const steps = check([
    'apps/pi_frame/test/widgets/bento_test.dart',
    'packages\\pi_frame_theme\\test\\theme_test.dart'
  ]);
  assert.deepEqual(withCwd(steps).slice(ANALYSIS_STEPS), [
    { command: 'flutter test test/widgets/bento_test.dart', cwd: 'apps/pi_frame' },
    { command: 'flutter test test/theme_test.dart', cwd: 'packages/pi_frame_theme' }
  ]);
});

test('check runs a TypeScript test from its compiled output, after the build step', () => {
  const steps = check([
    'apps/agentd/src/pi/test/jsonlFramer.test.ts',
    'packages/pcp-ts/src/test/index.test.ts',
    'tools/fake-pi/src/test/a.test.mts'
  ]);
  assert.deepEqual(withCwd(steps).slice(ANALYSIS_STEPS), [
    { command: 'node --test apps/agentd/dist/pi/test/jsonlFramer.test.js', cwd: undefined },
    { command: 'node --test packages/pcp-ts/dist/test/index.test.js', cwd: undefined },
    { command: 'node --test tools/fake-pi/dist/test/a.test.mjs', cwd: undefined }
  ]);
});

test('check refuses a TypeScript test outside a src folder, naming the compiled path convention', () => {
  assert.throws(() => check(['apps/agentd/test/a.test.ts']), /apps\/agentd\/test\/a\.test\.ts.*src\/.*dist\//s);
});

test('check runs a Node test file with node --test from the repository root', () => {
  const steps = check(['tools/guardrails/test/steps.test.mjs', 'tools/scripts/x.test.js', 'tools/a/b.test.cjs']);
  assert.deepEqual(withCwd(steps).slice(ANALYSIS_STEPS), [
    { command: 'node --test tools/guardrails/test/steps.test.mjs', cwd: undefined },
    { command: 'node --test tools/scripts/x.test.js', cwd: undefined },
    { command: 'node --test tools/a/b.test.cjs', cwd: undefined }
  ]);
});

test('check refuses a path it cannot route, naming the supported kinds', () => {
  for (const file of ['README.md', 'lib/main.dart', 'somewhere/else/x_test.dart', 'apps/agentd/a.test.ts']) {
    assert.throws(
      () => check([file]),
      (err) => {
        assert.match(err.message, new RegExp(file.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')));
        assert.match(err.message, /_test\.dart/);
        assert.match(err.message, /\.test\.mjs/);
        return true;
      }
    );
  }
});
