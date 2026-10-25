import test from 'node:test';
import assert from 'node:assert/strict';
import { getGitStatus, getGitDiff, checkIsGitRepo } from '../gitClient.js';
import * as path from 'path';

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
