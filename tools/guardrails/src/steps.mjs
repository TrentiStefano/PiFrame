/**
 * The single list of gate steps. `pnpm run verify` (tools/scripts/verify-ci.mjs) runs the `verify` tier and the
 * CI workflow (.github/workflows/ci.yml) runs the `ci` tier; a parity test fails when the workflow drifts from it.
 * `pnpm run check` (tools/scripts/check.mjs) runs the `check` tier: the fast, local-only inner loop.
 *
 * Pure: no I/O. A step's `command` starts with the program (`node` means the Node.js running the gate).
 * To add a check, add it here, then add the matching step to ci.yml (the parity test prints the exact YAML).
 */
import { toPosix } from './paths.mjs';

/** @typedef {'node' | 'flutter'} CiJob */
/** @typedef {{ name: string, command: string[], job: CiJob, cwd?: string }} Step */

// Steps that both the full gate and the `check` inner loop run.
/** @type {Step} */
const ESCAPE_HATCH_AUDIT = {
  job: 'node',
  name: 'Escape-hatch audit (baseline ratchet)',
  command: ['node', 'tools/scripts/audit-escape-hatches.mjs']
};
/** @type {Step} */
const DOC_LINKS = {
  job: 'node',
  name: 'Doc links (relative links and anchors resolve)',
  command: ['node', 'tools/scripts/check-doc-links.mjs']
};
/** @type {Step} */
const AGENT_MAP_CHECK = {
  job: 'node',
  name: 'AGENTS.md map check (length, paths, scripts)',
  command: ['node', 'tools/scripts/check-agent-map.mjs']
};
/** @type {Step} */
const BOUNDARY_CHECK = {
  job: 'node',
  name: 'Import boundaries (layers, daemon table, baseline)',
  command: ['node', 'tools/scripts/check-boundaries.mjs']
};
/** @type {Step} */
const TS_BUILD = { job: 'node', name: 'Build TypeScript packages', command: ['pnpm', '-r', 'run', 'build'] };
/** @type {Step} */
const TS_LINT = { job: 'node', name: 'TypeScript lint (tsc --noEmit)', command: ['pnpm', '-r', 'run', 'lint'] };
/** @type {Step} */
const FLUTTER_ANALYZE = {
  job: 'flutter',
  name: 'Flutter analyze (all projects)',
  command: ['node', 'tools/scripts/lint-flutter.mjs']
};

// DESIGN.md: Google's linter (errors and warnings fail) and its tokens against the shipped theme.
/** @type {Step} */
const DESIGN_LINT = {
  job: 'node',
  name: 'DESIGN.md lint (@google/design.md)',
  command: ['node', 'tools/scripts/lint-design.mjs']
};
/** @type {Step} */
const DESIGN_TOKENS = {
  job: 'node',
  name: 'DESIGN.md tokens match the theme',
  command: ['node', 'tools/scripts/check-design-tokens.mjs']
};

/** @type {Step[]} */
const GATE = [
  { job: 'node', name: 'Install dependencies (frozen lockfile)', command: ['pnpm', 'install', '--frozen-lockfile'] },
  {
    job: 'node',
    name: 'TypeScript formatting (Prettier)',
    command: ['node', 'tools/scripts/format.mjs', '--check', 'ts']
  },
  ESCAPE_HATCH_AUDIT,
  DOC_LINKS,
  AGENT_MAP_CHECK,
  BOUNDARY_CHECK,
  DESIGN_LINT,
  DESIGN_TOKENS,
  { job: 'node', name: 'Verify Pi target recon', command: ['node', 'tools/recon/verify.ts'] },
  { job: 'node', name: 'PCP schema validation', command: ['pnpm', '--filter', '@piframe/pcp-spec', 'run', 'test'] },
  TS_BUILD,
  TS_LINT,
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
  // Version metadata, plus the in-app changelog in check mode (it never writes). In a fresh checkout setup has just
  // generated the changelog, so that part only fails locally, on a stale copy left on disk.
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
  FLUTTER_ANALYZE,
  // test-flutter.js generates the in-app changelog first, like every other Flutter test path.
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
 * @property {string[]} [tests] repository-relative test files to run after analysis (`*_test.dart`,
 *   `*.test.mjs|cjs|js`, or a TypeScript `<package>/src/**\/*.test.ts` run from its compiled `dist/` copy)
 * @property {string[]} [flutterProjects] the Flutter project folders a Dart test file may belong to
 */

const TIERS = ['verify', 'ci', 'check'];
const FLUTTER_APP = 'apps/pi_frame';

const copy = (step) => ({ ...step, command: [...step.command] });

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
  const steps = GATE.map(copy);
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
  ESCAPE_HATCH_AUDIT,
  // Also Node only and under a second: a moved or deleted doc must not leave a broken link.
  DOC_LINKS,
  // Node only and under a second too: AGENTS.md stays short and names only paths and scripts that exist.
  AGENT_MAP_CHECK,
  BOUNDARY_CHECK,
  DESIGN_LINT,
  DESIGN_TOKENS,
  // agentd and e2e type-check against the other workspace packages' dist/*.d.ts, so they must be built first. The
  // build also refreshes the compiled TypeScript tests that `check` runs.
  TS_BUILD,
  TS_LINT,
  // The app's pubspec lists the untracked in-app changelog (apps/pi_frame/assets/CHANGELOG.md): flutter analyze
  // warns when it is missing and the Flutter tests bundle it, so generate it from CHANGELOG.md first.
  { job: 'node', name: 'Generate the in-app changelog', command: ['node', 'tools/scripts/sync-changelog.mjs'] },
  FLUTTER_ANALYZE
];

function checkSteps({ tests = [], flutterProjects = [] } = {}) {
  const steps = CHECK.map(copy);
  for (const test of tests) steps.push(testStep(toPosix(test).replace(/^\.\//, ''), flutterProjects));
  return steps;
}

/** TypeScript test sources and the extension their compiled copy has. */
const TS_TEST = /\.test\.(ts|tsx|mts|cts)$/;
const COMPILED_EXTENSION = { ts: 'js', tsx: 'js', mts: 'mjs', cts: 'cjs' };
/** `<package>/src/<rest>` → `<package>/dist/<rest>`: every TypeScript package compiles `src` to `dist` (tsconfig). */
const SRC_SEGMENT = /^(.*?\/)?src\//;

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
  const ts = file.match(TS_TEST);
  if (ts && SRC_SEGMENT.test(file)) {
    const compiled = file
      .replace(SRC_SEGMENT, (_, pkg = '') => `${pkg}dist/`)
      .replace(TS_TEST, `.test.${COMPILED_EXTENSION[ts[1]]}`);
    return {
      job: 'node',
      name: `Node test ${compiled} (compiled from ${file})`,
      command: ['node', '--test', compiled]
    };
  }
  throw new Error(
    `check: cannot run "${file}". Supported test files: Dart "*_test.dart" inside a Flutter project ` +
      `(${flutterProjects.join(', ')}), run with flutter test; Node "*.test.mjs", "*.test.cjs" or "*.test.js", ` +
      'run with node --test; TypeScript "<package>/src/**/*.test.ts", run from its compiled ' +
      '"<package>/dist/**/*.test.js" after the build step.' +
      (ts ? ' This TypeScript test is not under a src/ folder: pass its compiled dist/ file instead.' : '')
  );
}
