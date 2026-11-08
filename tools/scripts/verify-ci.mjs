#!/usr/bin/env node
/**
 * Local pre-pull-request verification.
 *
 * Runs, on this machine, the steps the GitHub workflows (ci.yml + the validation job and desktop/web
 * builds of release.yml) run after a merge to `main`, so a broken change is caught before it burns
 * runner minutes. It verifies what `main` will look like AFTER the pull request: the committed HEAD is
 * checked out in a temporary worktree and `origin/main` is merged into it first.
 *
 *   pnpm run verify                 CI + release validation
 *   pnpm run verify -- --release    + flutter build (desktop of this OS) and web, as in the release job
 *   pnpm run verify -- --e2e        + emulated-iPhone remote web test (tools/remote-e2e)
 *   pnpm run verify -- --force      ignore the "already verified" cache
 *   pnpm run verify -- --no-merge   test HEAD alone (skip merging origin/main)
 *   pnpm run verify -- --keep       keep the temporary worktree (debugging)
 *   pnpm run verify -- --verbose    stream every step's output instead of only showing failures
 *
 * Exit code 0 only when every step passed. See docs/pr-verification.md.
 */
import { spawnSync, execFileSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const IS_WIN = process.platform === 'win32';
const args = new Set(process.argv.slice(2));
const opt = {
  release: args.has('--release'),
  e2e: args.has('--e2e'),
  force: args.has('--force'),
  noMerge: args.has('--no-merge'),
  keep: args.has('--keep'),
  verbose: args.has('--verbose')
};
const BASE_REF = process.env.VERIFY_BASE || 'origin/main';

const c = (code, s) => (process.stdout.isTTY ? `\x1b[${code}m${s}\x1b[0m` : s);
const green = (s) => c(32, s);
const red = (s) => c(31, s);
const yellow = (s) => c(33, s);
const dim = (s) => c(2, s);

function git(cwd, ...gitArgs) {
  return execFileSync('git', gitArgs, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

function fail(message) {
  console.error(red(`\n✖ ${message}`));
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Preconditions
// ---------------------------------------------------------------------------

if (git(REPO, 'status', '--porcelain').length > 0) {
  fail(
    'The working tree has uncommitted changes. verify checks the committed HEAD merged with ' +
      `${BASE_REF}; commit (or stash) first so what is verified is what you push.`
  );
}

console.log(dim(`Fetching ${BASE_REF}...`));
try {
  const [remote, branch] = BASE_REF.split('/');
  git(REPO, 'fetch', '--quiet', remote, branch);
} catch (err) {
  console.warn(yellow(`! Could not fetch ${BASE_REF} (${String(err.message).split('\n')[0]}); using the local ref.`));
}

let baseSha;
try {
  baseSha = git(REPO, 'rev-parse', BASE_REF);
} catch {
  fail(`Cannot resolve ${BASE_REF}.`);
}
const headSha = git(REPO, 'rev-parse', 'HEAD');
const treeSha = git(REPO, 'rev-parse', 'HEAD^{tree}');
const gitDir = path.resolve(REPO, git(REPO, 'rev-parse', '--git-common-dir'));
const stateDir = path.join(gitDir, 'verify-ci');
fs.mkdirSync(stateDir, { recursive: true });

// A result is valid for the same content (tree), the same base and the same level of checking.
const level = [opt.release ? 'release' : 'ci', opt.e2e ? 'e2e' : '', opt.noMerge ? 'nomerge' : ''].filter(Boolean).join('+');
const cacheKey = `${treeSha}-${opt.noMerge ? 'x' : baseSha}-${level}`;
const cacheFile = path.join(stateDir, `${cacheKey}.ok`);

if (!opt.force && fs.existsSync(cacheFile)) {
  console.log(green(`✔ Already verified (${level}): tree ${treeSha.slice(0, 10)} on ${BASE_REF} ${baseSha.slice(0, 10)}.`));
  console.log(dim('  Use --force to run again.'));
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Environment drift warnings (workflows pin versions; the local machine may differ)
// ---------------------------------------------------------------------------

function pinned(re) {
  try {
    const yml = fs.readFileSync(path.join(REPO, '.github/workflows/release.yml'), 'utf8');
    return yml.match(re)?.[1];
  } catch {
    return undefined;
  }
}
const warnings = [];
const wfNode = pinned(/node-version:\s*['"]?(\d+)/);
if (wfNode && process.versions.node.split('.')[0] !== wfNode) {
  warnings.push(`Node ${process.versions.node} locally, workflows use Node ${wfNode}.`);
}
const wfFlutter = pinned(/flutter-version:\s*['"]?([\d.]+)/);
try {
  const out = spawnSync('flutter', ['--version'], { encoding: 'utf8', shell: IS_WIN }).stdout || '';
  const local = out.match(/Flutter\s+([\d.]+)/)?.[1];
  if (wfFlutter && local && local !== wfFlutter) warnings.push(`Flutter ${local} locally, workflows pin ${wfFlutter}.`);
} catch {
  // flutter missing is reported by the first Flutter step
}
if (process.platform !== 'linux') {
  warnings.push(`Running on ${process.platform}: workflows run on Linux (and Windows/macOS for installers); path/case differences are not covered.`);
}
for (const w of warnings) console.warn(yellow(`! ${w}`));

// ---------------------------------------------------------------------------
// Temporary worktree = HEAD + origin/main
// ---------------------------------------------------------------------------

// NOT under os.tmpdir(): some agentd tests use process.cwd() as a session cwd and the session index
// ignores sessions located in the OS temp dir, so they fail when the repo itself lives there.
const work = `${REPO}-verify-${process.pid}`;
let worktreeCreated = false;
function cleanup() {
  if (!worktreeCreated || opt.keep) return;
  try {
    git(REPO, 'worktree', 'remove', '--force', work);
  } catch {
    fs.rmSync(work, { recursive: true, force: true });
    try {
      git(REPO, 'worktree', 'prune');
    } catch {
      // ignore
    }
  }
}
process.on('exit', cleanup);
process.on('SIGINT', () => process.exit(130));

console.log(dim(`Preparing worktree ${work} ...`));
git(REPO, 'worktree', 'add', '--detach', '--quiet', work, 'HEAD');
worktreeCreated = true;

if (!opt.noMerge) {
  const ahead = git(work, 'rev-list', '--count', `HEAD..${baseSha}`);
  if (ahead === '0') {
    console.log(dim(`HEAD already contains ${BASE_REF}.`));
  } else {
    try {
      git(work, '-c', 'user.name=verify', '-c', 'user.email=verify@localhost', 'merge', '--no-edit', '--quiet', baseSha);
      console.log(dim(`Merged ${BASE_REF} (${ahead} commit(s)) into the verification worktree.`));
    } catch (err) {
      console.error(String(err.stderr || err.message).trim());
      fail(`Merging ${BASE_REF} into your branch conflicts. Merge or rebase ${BASE_REF} first, resolve the conflicts, commit, then run verify again.`);
    }
  }
}

// ---------------------------------------------------------------------------
// Steps (mirror .github/workflows/ci.yml and the release.yml validate/build jobs)
// ---------------------------------------------------------------------------

const pkg = JSON.parse(fs.readFileSync(path.join(work, 'package.json'), 'utf8'));
const appVersion = pkg.version;
const flutterPlatform = { win32: 'windows', darwin: 'macos', linux: 'linux' }[process.platform];

/** @type {{name: string, cmd: string, args: string[], cwd?: string, node?: boolean}[]} */
const steps = [
  { name: 'Install dependencies (frozen lockfile)', cmd: 'pnpm', args: ['install', '--frozen-lockfile'] },
  { name: 'Verify Pi target recon', cmd: process.execPath, args: ['tools/recon/verify.ts'], node: true },
  { name: 'PCP schema validation', cmd: 'pnpm', args: ['--filter', '@piframe/pcp-spec', 'run', 'test'] },
  { name: 'Build TypeScript packages', cmd: 'pnpm', args: ['-r', 'run', 'build'] },
  { name: 'Node tests (all packages)', cmd: 'pnpm', args: ['-r', 'run', 'test'] },
  { name: 'Third-party notices up to date', cmd: 'pnpm', args: ['run', 'check:notices'] },
  { name: 'Version metadata synchronized', cmd: 'pnpm', args: ['run', 'check:version'] },
  { name: 'Daemon bundle contents', cmd: 'pnpm', args: ['run', 'check:agentd-bundle'] },
  { name: 'Daemon bundle smoke test', cmd: 'pnpm', args: ['run', 'smoke:agentd-bundle'] },
  { name: 'Windows release-name tests', cmd: process.execPath, args: ['--test', 'tools/scripts/test-windows-release-name.test.mjs'], node: true },
  { name: 'Flutter dependencies', cmd: process.execPath, args: ['tools/scripts/setup-flutter.js'], node: true },
  { name: 'Flutter analyze (all projects)', cmd: process.execPath, args: ['tools/scripts/lint-flutter.js'], node: true },
  { name: 'Flutter tests (all projects)', cmd: process.execPath, args: ['tools/scripts/test-flutter.js'], node: true }
];

if (opt.release || opt.e2e) {
  steps.push({
    name: 'Build Flutter web app (as in the release job)',
    cmd: 'flutter',
    args: ['build', 'web', '--release', '--no-web-resources-cdn', '--pwa-strategy=none', `--dart-define=PI_FRAME_VERSION=${appVersion}`],
    cwd: 'apps/pi_frame'
  });
}
if (opt.release) {
  steps.push({
    name: `Build Flutter ${flutterPlatform} desktop app (as in the release job)`,
    cmd: 'flutter',
    args: ['build', flutterPlatform, '--release', '--build-name', appVersion, '--build-number', '1', `--dart-define=PI_FRAME_VERSION=${appVersion}`],
    cwd: 'apps/pi_frame'
  });
}
if (opt.e2e) {
  steps.push({ name: 'Emulated-iPhone remote web test', cmd: process.execPath, args: ['tools/remote-e2e/remote-iphone-e2e.mjs'], node: true });
}

const logFile = path.join(stateDir, 'last.log');
fs.writeFileSync(logFile, '');

function tail(file, lines = 70) {
  try {
    return fs.readFileSync(file, 'utf8').split(/\r?\n/).slice(-lines).join('\n');
  } catch {
    return '';
  }
}

const started = Date.now();
console.log(`\nVerifying (${level}) tree ${treeSha.slice(0, 10)} + ${opt.noMerge ? 'no merge' : `${BASE_REF} ${baseSha.slice(0, 10)}`}`);
console.log(dim(`Output log: ${logFile}\n`));

let index = 0;
for (const step of steps) {
  index += 1;
  const label = `[${index}/${steps.length}] ${step.name}`;
  const t0 = Date.now();
  process.stdout.write(`${label} ... `);
  fs.appendFileSync(logFile, `\n===== ${label} =====\n`);
  const fd = fs.openSync(logFile, 'a');
  const result = spawnSync(step.cmd, step.args, {
    cwd: path.join(work, step.cwd || '.'),
    stdio: opt.verbose ? 'inherit' : ['ignore', fd, fd],
    shell: IS_WIN && !step.node,
    env: { ...process.env, CI: 'true' }
  });
  fs.closeSync(fd);
  const secs = ((Date.now() - t0) / 1000).toFixed(1);
  if (result.status === 0) {
    console.log(green(`ok`) + dim(` (${secs}s)`));
    continue;
  }
  console.log(red('FAILED') + dim(` (${secs}s)`));
  if (!opt.verbose) {
    console.error(dim('\n--- last lines of the step output ---'));
    console.error(tail(logFile));
    console.error(dim('--- end ---'));
  }
  fail(`Step failed: ${step.name}. Fix it, commit, and run verify again (nothing was pushed or opened).`);
}

// Some tests regenerate tracked screenshots. Not a CI failure, but they must never be committed by accident.
const dirty = git(work, 'status', '--porcelain');
if (dirty.length > 0) {
  const files = dirty.split(/\r?\n/).map((l) => l.trim());
  const header =
    `\n! The test run rewrote ${files.length} tracked file(s) in the verification worktree (discarded with it). ` +
    'If the same files show up as modified in your working tree after running the tests yourself, do not commit them:';
  console.warn(yellow(header));
  console.warn(files.slice(0, 10).map((l) => `    ${l}`).join('\n'));
}

fs.writeFileSync(cacheFile, JSON.stringify({ head: headSha, tree: treeSha, base: baseSha, level, at: new Date().toISOString() }));
const total = ((Date.now() - started) / 60000).toFixed(1);
console.log(green(`\n✔ All ${steps.length} steps passed in ${total} min.`) + dim(`  Result cached for this exact content (${level}).`));
