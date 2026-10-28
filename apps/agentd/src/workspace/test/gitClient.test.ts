import test from 'node:test';
import assert from 'node:assert/strict';
import { getGitStatus, getGitDiff, checkIsGitRepo } from '../gitClient.js';
import * as path from 'path';
import * as fs from 'node:fs';
import * as os from 'node:os';
import { execFileSync } from 'node:child_process';

test('gitClient: detects current repository status', async () => {
  const currentCwd = process.cwd();
  const repoCheck = await checkIsGitRepo(currentCwd);
  assert.equal(repoCheck.isRepo, true, 'Current workspace must be recognized as a Git repo');
  assert.ok(repoCheck.rootPath, 'Root path must be non-empty');

  const status = await getGitStatus(currentCwd);
  assert.equal(status.isRepository, true);
  assert.ok(status.branch, 'Branch name must be present');
  assert.ok(Array.isArray(status.files));
});

test('gitClient: handles non-git directory gracefully without throwing', async () => {
  const root = path.parse(process.cwd()).root;
  const status = await getGitStatus(root);
  assert.equal(status.isRepository, false);
  assert.equal(status.files.length, 0);
  assert.equal(status.totalAdditions, 0);
});

test('gitClient: getGitDiff returns a string', async () => {
  const diff = await getGitDiff(process.cwd());
  assert.equal(typeof diff, 'string');
});

test('gitClient: parseWslPath and toWslUncPath helper functions', async () => {
  const { parseWslPath, toWslUncPath } = await import('../gitClient.js');
  if (process.platform === 'win32') {
    const wsl = parseWslPath('\\\\wsl.localhost\\Ubuntu\\home\\user\\repo');
    assert.ok(wsl);
    assert.equal(wsl.distro, 'Ubuntu');
    assert.equal(wsl.linuxPath, '/home/user/repo');
    assert.equal(wsl.uncPrefix, '\\\\wsl.localhost\\Ubuntu');

    const unc = toWslUncPath('/home/user/repo', wsl.uncPrefix);
    assert.equal(unc, '\\\\wsl.localhost\\Ubuntu\\home\\user\\repo');

    const wslDollar = parseWslPath('//wsl$/Debian/var/www/');
    assert.ok(wslDollar);
    assert.equal(wslDollar.distro, 'Debian');
    assert.equal(wslDollar.linuxPath, '/var/www');

    const nonWsl = parseWslPath('C:\\Users\\test');
    assert.equal(nonWsl, null);
  } else {
    const nonWin = parseWslPath('/home/user/repo');
    assert.equal(nonWin, null);
  }
});

function createTempRepo(t: test.TestContext): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-review-'));
  t.after(() => fs.rmSync(repo, { recursive: true, force: true }));
  execFileSync('git', ['init', '-q'], { cwd: repo });
  execFileSync('git', ['config', 'user.email', 'test@example.com'], { cwd: repo });
  execFileSync('git', ['config', 'user.name', 'PiFrame Test'], { cwd: repo });
  return repo;
}

function git(repo: string, ...args: string[]): void {
  execFileSync('git', args, { cwd: repo, stdio: 'ignore' });
}

test('gitClient: reports net HEAD-to-working-tree counts including staged and unstaged edits', async (t) => {
  const repo = createTempRepo(t);
  fs.writeFileSync(path.join(repo, 'tracked.txt'), 'before\nstays\n');
  git(repo, 'add', 'tracked.txt');
  git(repo, 'commit', '-qm', 'base');

  fs.writeFileSync(path.join(repo, 'tracked.txt'), 'staged\nstays\n');
  git(repo, 'add', 'tracked.txt');
  fs.writeFileSync(path.join(repo, 'tracked.txt'), 'staged\nworking\n');

  const status = await getGitStatus(repo);
  assert.deepEqual(
    status.files.map(({ path: file, additions, deletions }) => ({ file, additions, deletions })),
    [{ file: 'tracked.txt', additions: 2, deletions: 2 }]
  );
  assert.equal(status.totalAdditions, 2);
  assert.equal(status.totalDeletions, 2);
  const diff = await getGitDiff(repo, 'tracked.txt');
  assert.match(diff, /-before/);
  assert.match(diff, /\+staged/);
  assert.match(diff, /-stays/);
  assert.match(diff, /\+working/);
});

test('gitClient: clean tracked files have no review diff or fabricated additions', async (t) => {
  const repo = createTempRepo(t);
  fs.writeFileSync(path.join(repo, 'clean.txt'), 'unchanged\n');
  git(repo, 'add', 'clean.txt');
  git(repo, 'commit', '-qm', 'base');

  const status = await getGitStatus(repo);
  assert.equal(status.files.length, 0);
  assert.equal(status.totalAdditions, 0);
  assert.equal(status.totalDeletions, 0);
  assert.equal(await getGitDiff(repo, 'clean.txt'), '');
});

test('gitClient: counts untracked multiline files without a final newline', async (t) => {
  const repo = createTempRepo(t);
  fs.writeFileSync(path.join(repo, 'new file.txt'), 'first\nsecond');

  const status = await getGitStatus(repo);
  assert.equal(status.files[0]?.path, 'new file.txt');
  assert.equal(status.files[0]?.additions, 2);
  assert.equal(status.files[0]?.deletions, 0);
  assert.equal(status.totalAdditions, 2);
  assert.equal(status.totalDeletions, 0);
  const diff = await getGitDiff(repo, 'new file.txt');
  assert.match(diff, /\+first/);
  assert.match(diff, /\+second/);
  assert.match(diff, /No newline at end of file/);
});

test('gitClient: supports an unborn repository with staged files', async (t) => {
  const repo = createTempRepo(t);
  fs.writeFileSync(path.join(repo, 'first commit.txt'), 'one\ntwo\n');
  git(repo, 'add', 'first commit.txt');

  const status = await getGitStatus(repo);
  assert.equal(status.files[0]?.path, 'first commit.txt');
  assert.equal(status.files[0]?.additions, 2);
  assert.equal(status.totalAdditions, 2);
  const diff = await getGitDiff(repo, 'first commit.txt');
  assert.match(diff, /\+one/);
  assert.match(diff, /\+two/);
});

test('gitClient: parses NUL numstat paths and rename paths containing spaces', async (t) => {
  const repo = createTempRepo(t);
  fs.writeFileSync(path.join(repo, 'old name.txt'), 'one\ntwo\nthree\nfour\n');
  git(repo, 'add', 'old name.txt');
  git(repo, 'commit', '-qm', 'base');
  git(repo, 'mv', 'old name.txt', 'new name.txt');
  const renamed = await getGitStatus(repo);
  assert.equal(renamed.files[0]?.path, 'new name.txt');
  assert.equal(renamed.files[0]?.status, 'renamed');
  assert.match(await getGitDiff(repo, 'new name.txt'), /rename from old name.txt/);

  const specialPath = 'special #1 café name.txt';
  fs.writeFileSync(path.join(repo, specialPath), 'a\nb');
  const status = await getGitStatus(repo);
  const special = status.files.find((file) => file.path === specialPath);
  assert.ok(special);
  assert.equal(special.additions, 2);
  assert.equal(special.deletions, 0);
});

test('gitClient: binary files report zero line counts and retain binary diff output', async (t) => {
  const repo = createTempRepo(t);
  const bytes = Buffer.from([0, 1, 2, 255, 0]);
  fs.writeFileSync(path.join(repo, 'binary.bin'), bytes);

  const status = await getGitStatus(repo);
  assert.equal(status.files[0]?.additions, 0);
  assert.equal(status.files[0]?.deletions, 0);
  assert.equal(status.totalAdditions, 0);
  assert.equal(status.totalDeletions, 0);
  assert.match(await getGitDiff(repo, 'binary.bin'), /Binary files .* differ/);
});

test('gitClient: detects WSL repository if WSL path exists', async () => {
  const testWslPath = '\\\\wsl.localhost\\LMD_env\\home\\strenti\\Repos\\Flutter\\BeamControl_main';
  const fs = await import('fs');
  if (fs.existsSync(testWslPath)) {
    const res = await checkIsGitRepo(testWslPath);
    assert.equal(res.isRepo, true);
    assert.ok(res.rootPath?.includes('BeamControl_main'));

    const status = await getGitStatus(testWslPath);
    assert.equal(status.isRepository, true);
    assert.ok(status.branch);
  }
});
