/**
 * The single list of gate steps. `pnpm run verify` (tools/scripts/verify-ci.mjs) runs the `verify` tier and the
 * CI workflow (.github/workflows/ci.yml) runs the `ci` tier; a parity test fails when the workflow drifts from it.
 * `pnpm run check` (tools/scripts/check.mjs) runs the `check` tier: the fast, local-only inner loop.
 *
 * Pure: no I/O. A step's `command` starts with the program (`node` means the Node.js running the gate).
 * To add a check, add it here, then add the matching step to ci.yml (the parity test prints the exact YAML).
 */

/** @typedef {'node' | 'flutter'} CiJob */
/** @typedef {{ name: string, command: string[], job: CiJob, cwd?: string }} Step */

/** @type {Step[]} */
const GATE = [
  { job: 'node', name: 'Install dependencies (frozen lockfile)', command: ['pnpm', 'install', '--frozen-lockfile'] },
  {
    job: 'node',
    name: 'TypeScript formatting (Prettier)',
    command: ['node', 'tools/scripts/format.mjs', '--check', 'ts']
  },
  {
    job: 'node',
    name: 'Escape-hatch audit (baseline ratchet)',
    command: ['node', 'tools/scripts/audit-escape-hatches.mjs']
  },
  { job: 'node', name: 'Verify Pi target recon', command: ['node', 'tools/recon/verify.ts'] },
  { job: 'node', name: 'PCP schema validation', command: ['pnpm', '--filter', '@piframe/pcp-spec', 'run', 'test'] },
  { job: 'node', name: 'Build TypeScript packages', command: ['pnpm', '-r', 'run', 'build'] },
  { job: 'node', name: 'TypeScript lint (tsc --noEmit)', command: ['pnpm', '-r', 'run', 'lint'] },
  { job: 'node', name: 'Codegen parity (schema, TypeScript, Dart)', command: ['node', 'tools/codegen/generate.js'] },
  { job: 'node', name: 'Node tests (all packages)', command: ['pnpm', '-r', 'run', 'test'] },
  { job: 'node', name: 'Third-party notices up to date', command: ['pnpm', 'run', 'check:notices'] },
  { job: 'node', name: 'Daemon bundle contents', command: ['pnpm', 'run', 'check:agentd-bundle'] },
  { job: 'node', name: 'Daemon bundle smoke test', command: ['pnpm', 'run', 'smoke:agentd-bundle'] },
  {
    job: 'node',
    name: 'Windows release-name tests',
    command: ['node', '--test', 'tools/scripts/test-windows-release-name.test.mjs']
  },
  // Flutter setup generates the in-app changelog (apps/pi_frame/assets/CHANGELOG.md, untracked) from CHANGELOG.md.
  { job: 'flutter', name: 'Flutter dependencies', command: ['node', 'tools/scripts/setup-flutter.js'] },
  // Check mode: fails on a missing or stale in-app changelog and never writes. Runs after setup, which generates it.
  {
    job: 'flutter',
    name: 'Version metadata and in-app changelog synchronized',
    command: ['node', 'tools/scripts/check-version-sync.mjs']
  },
  {
    job: 'flutter',
    name: 'Dart formatting (dart format)',
    command: ['node', 'tools/scripts/format.mjs', '--check', 'dart']
  },
  { job: 'flutter', name: 'Flutter analyze (all projects)', command: ['node', 'tools/scripts/lint-flutter.js'] },
  { job: 'flutter', name: 'Flutter tests (all projects)', command: ['node', 'tools/scripts/test-flutter.js'] }
];

/**
 * @typedef {object} StepOptions
 * @property {boolean} [release] add the web and desktop release builds (as in the release workflow)
 * @property {boolean} [e2e] add the web build and the emulated-iPhone remote web test
 * @property {'windows' | 'macos' | 'linux'} [platform] desktop platform for the release build
 * @property {string} [appVersion] version passed to the Flutter builds
 */

/**
 * @typedef {object} CheckOptions
 * @property {string[]} [tests] repository-relative test files to run after analysis (`*_test.dart` or `*.test.mjs|cjs|js`)
 * @property {string[]} [flutterProjects] the Flutter project folders a Dart test file may belong to
 */

const TIERS = ['verify', 'ci', 'check'];
const FLUTTER_APP = 'apps/pi_frame';

/**
 * @param {'verify' | 'ci' | 'check'} tier `verify`: the local full gate. `ci`: the same gate, as the CI workflow runs
 *   it (release builds and e2e stay in the release workflow and in `verify --release` / `--e2e`). `check`: the inner
 *   loop, static analysis plus the given test files, in the current tree (no install, worktree or merge).
 * @param {StepOptions & CheckOptions} [options] release/e2e options for `verify`, test files for `check`
 * @returns {Step[]}
 */
export function stepList(tier, options = {}) {
  if (!TIERS.includes(tier)) throw new Error(`stepList: unknown tier "${tier}". Known tiers: ${TIERS.join(', ')}.`);
  if (tier === 'check') return checkSteps(options);
  const steps = GATE.map((step) => ({ ...step, command: [...step.command] }));
  const { release = false, e2e = false, platform, appVersion } = tier === 'verify' ? options : {};
  if (!release && !e2e) return steps;

  if (!appVersion) throw new Error('stepList: release and e2e builds need options.appVersion (package.json version).');
  if (release && !platform)
    throw new Error('stepList: a release build needs options.platform (windows, macos or linux).');
  const define = `--dart-define=PI_FRAME_VERSION=${appVersion}`;
  steps.push({
    job: 'flutter',
    name: 'Build Flutter web app (as in the release job)',
    command: ['flutter', 'build', 'web', '--release', '--no-web-resources-cdn', '--pwa-strategy=none', define],
    cwd: FLUTTER_APP
  });
  if (release) {
    steps.push({
      job: 'flutter',
      name: `Build Flutter ${platform} desktop app (as in the release job)`,
      command: ['flutter', 'build', platform, '--release', '--build-name', appVersion, '--build-number', '1', define],
      cwd: FLUTTER_APP
    });
  }
  if (e2e) {
    steps.push({
      job: 'node',
      name: 'Emulated-iPhone remote web test',
      command: ['node', 'tools/remote-e2e/remote-iphone-e2e.mjs']
    });
  }
  return steps;
}

/** The `check` tier: the escape-hatch audit and static analysis only, in the current working tree. */
const CHECK = [
  // First: it needs only Node and fails in under a second when an escape hatch was added or removed.
  {
    job: 'node',
    name: 'Escape-hatch audit (baseline ratchet)',
    command: ['node', 'tools/scripts/audit-escape-hatches.mjs']
  },
  // agentd and e2e type-check against the other workspace packages' dist/*.d.ts, so they must be built first.
  { job: 'node', name: 'Build TypeScript packages', command: ['pnpm', '-r', 'run', 'build'] },
  { job: 'node', name: 'TypeScript lint (tsc --noEmit)', command: ['pnpm', '-r', 'run', 'lint'] },
  { job: 'flutter', name: 'Flutter analyze (all projects)', command: ['node', 'tools/scripts/lint-flutter.js'] }
];

function checkSteps({ tests = [], flutterProjects = [] } = {}) {
  const steps = CHECK.map((step) => ({ ...step, command: [...step.command] }));
  for (const test of tests) steps.push(testStep(test.replaceAll('\\', '/').replace(/^\.\//, ''), flutterProjects));
  return steps;
}

/** @returns {Step} */
function testStep(file, flutterProjects) {
  if (file.endsWith('_test.dart')) {
    const project = flutterProjects.find((dir) => file.startsWith(`${dir}/`));
    if (project) {
      return {
        job: 'flutter',
        name: `Flutter test ${file}`,
        command: ['flutter', 'test', file.slice(project.length + 1)],
        cwd: project
      };
    }
  }
  if (/\.test\.(mjs|cjs|js)$/.test(file)) {
    return { job: 'node', name: `Node test ${file}`, command: ['node', '--test', file] };
  }
  throw new Error(
    `check: cannot run "${file}". Supported test files: Dart "*_test.dart" inside a Flutter project ` +
      `(${flutterProjects.join(', ')}), run with flutter test; Node "*.test.mjs", "*.test.cjs" or "*.test.js", ` +
      'run with node --test. TypeScript tests run from their build output: pass the compiled dist/**/*.test.js.'
  );
}
