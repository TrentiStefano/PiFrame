#!/usr/bin/env node
/**
 * Local pre-pull-request verification.
 *
 * Runs, on this machine, the `verify` tier of the shared step list (tools/guardrails/src/steps.mjs): the
 * same steps ci.yml runs on every pull request, plus the release.yml desktop/web builds with --release, so a
 * broken change is caught before it burns runner minutes. It verifies what `main` will look like AFTER the
 * pull request: the committed HEAD is checked out in a temporary worktree and `origin/main` is merged into it first.
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
 *
 * Folder decisions are pure (tools/guardrails/src/verify-worktrees.mjs); reading and deleting folders is
 * tools/scripts/verify-folders.mjs. This file only sequences the run.
 */
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {
  dirtyVerifyTreeFailure,
  leftoverVerifyFailure,
  selectLeftoverVerifyFolders,
  selectStaleVerifyWorktrees
} from '../guardrails/src/index.mjs';
import { folderExists, git, normalizePath, removeFolder, verifyFolderGroups } from './verify-folders.mjs';

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

// NOT under os.tmpdir(): some agentd tests use process.cwd() as a session cwd and the session index
// ignores sessions located in the OS temp dir, so they fail when the repo itself lives there.
const work = `${REPO}-verify-${process.pid}`;

const c = (code, s) => (process.stdout.isTTY ? `\x1b[${code}m${s}\x1b[0m` : s);
const green = (s) => c(32, s);
const red = (s) => c(31, s);
const yellow = (s) => c(33, s);
const dim = (s) => c(2, s);

function fail(message) {
  console.error(red(`\n✖ ${message}`));
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Verify folders: stale ones from earlier runs, and the leftovers this run must not leave
// ---------------------------------------------------------------------------

function removeStaleVerifyWorktrees(gitDir) {
  for (const { parent, repoName, folders } of verifyFolderGroups({ repo: REPO, gitDir })) {
    for (const name of selectStaleVerifyWorktrees({ repoName, currentPid: process.pid, folders })) {
      const dir = path.join(parent, name);
      console.log(
        removeFolder(dir)
          ? dim(`Removed stale verify worktree ${name}.`)
          : yellow(`! Could not delete stale verify worktree ${name}; verify fails at the end until it is removed.`)
      );
    }
  }
  try {
    git(REPO, 'worktree', 'prune');
  } catch {
    // nothing to prune
  }
}

/**
 * Folders this run must leave gone: its own, and stale ones. Another live run's folder is not counted.
 * With --keep, this run's own folder is kept on purpose.
 */
function leftoverFolders(gitDir) {
  return verifyFolderGroups({ repo: REPO, gitDir })
    .flatMap(({ parent, repoName, folders }) =>
      selectLeftoverVerifyFolders({ repoName, currentPid: process.pid, folders }).map((name) => path.join(parent, name))
    )
    .filter((dir) => folderExists(dir) && !(opt.keep && normalizePath(dir) === normalizePath(work)));
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
removeStaleVerifyWorktrees(gitDir);

// A result is valid for the same content (tree), the same base and the same level of checking.
const level = [opt.release ? 'release' : 'ci', opt.e2e ? 'e2e' : '', opt.noMerge ? 'nomerge' : '']
  .filter(Boolean)
  .join('+');
const cacheKey = `${treeSha}-${opt.noMerge ? 'x' : baseSha}-${level}`;
const cacheFile = path.join(stateDir, `${cacheKey}.ok`);

if (!opt.force && fs.existsSync(cacheFile)) {
  console.log(
    green(`✔ Already verified (${level}): tree ${treeSha.slice(0, 10)} on ${BASE_REF} ${baseSha.slice(0, 10)}.`)
  );
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
  warnings.push(
    `Running on ${process.platform}: workflows run on Linux (and Windows/macOS for installers); path/case differences are not covered.`
  );
}
for (const w of warnings) console.warn(yellow(`! ${w}`));

// ---------------------------------------------------------------------------
// Temporary worktree = HEAD + origin/main
// ---------------------------------------------------------------------------

let worktreeCreated = false;
let worktreeCleaned = false;
function cleanup() {
  if (!worktreeCreated || worktreeCleaned || opt.keep) return;
  worktreeCleaned = true;
  try {
    git(REPO, 'worktree', 'remove', '--force', work);
  } catch {
    // git cannot remove it (long paths): removed below
  }
  removeFolder(work);
  try {
    git(REPO, 'worktree', 'prune');
  } catch {
    // ignore
  }
}
process.on('exit', () => {
  cleanup();
  const left = leftoverFolders(gitDir);
  if (left.length > 0) console.error(red(leftoverVerifyFailure({ leftovers: left })));
});
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
      git(
        work,
        '-c',
        'user.name=verify',
        '-c',
        'user.email=verify@localhost',
        'merge',
        '--no-edit',
        '--quiet',
        baseSha
      );
      console.log(dim(`Merged ${BASE_REF} (${ahead} commit(s)) into the verification worktree.`));
    } catch (err) {
      console.error(String(err.stderr || err.message).trim());
      fail(
        `Merging ${BASE_REF} into your branch conflicts. Merge or rebase ${BASE_REF} first, resolve the conflicts, commit, then run verify again.`
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Steps: the shared step list (tools/guardrails), the same one ci.yml follows
// ---------------------------------------------------------------------------

const pkg = JSON.parse(fs.readFileSync(path.join(work, 'package.json'), 'utf8'));
// Loaded from the worktree, so the steps are the ones of what `main` will be after the merge.
const { stepList } = await import(pathToFileURL(path.join(work, 'tools/guardrails/src/index.mjs')).href);
const steps = stepList('verify', {
  release: opt.release,
  e2e: opt.e2e,
  platform: { win32: 'windows', darwin: 'macos', linux: 'linux' }[process.platform],
  appVersion: pkg.version
}).map(({ name, command: [program, ...args], cwd }) => {
  // `node` steps run on this Node.js, without a shell; everything else goes through the shell on Windows (.cmd shims).
  const node = program === 'node';
  return { name, cmd: node ? process.execPath : program, args, cwd, node };
});

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
console.log(
  `\nVerifying (${level}) tree ${treeSha.slice(0, 10)} + ${opt.noMerge ? 'no merge' : `${BASE_REF} ${baseSha.slice(0, 10)}`}`
);
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

// The tests run in the verification worktree, so the clean-tree check is made there: a test that writes a tracked file
// is a failure that names the file, not a warning.
const dirtyFailure = dirtyVerifyTreeFailure({
  dirtyFiles: git(work, 'status', '--porcelain')
    .split(/\r?\n/)
    .filter((line) => line.length > 0)
});
if (dirtyFailure) fail(dirtyFailure);

// The verification worktree must be gone, and the repository's own working tree must be untouched.
cleanup();
const left = leftoverFolders(gitDir);
if (left.length > 0) fail(leftoverVerifyFailure({ leftovers: left }));
const tree = git(REPO, 'status', '--porcelain');
if (tree.length > 0) {
  fail(`The working tree is not clean after verify (verify never edits it):\n${tree}`);
}

fs.writeFileSync(
  cacheFile,
  JSON.stringify({ head: headSha, tree: treeSha, base: baseSha, level, at: new Date().toISOString() })
);
const total = ((Date.now() - started) / 60000).toFixed(1);
console.log(
  green(`\n✔ All ${steps.length} steps passed in ${total} min.`) +
    dim(`  Result cached for this exact content (${level}).`)
);
