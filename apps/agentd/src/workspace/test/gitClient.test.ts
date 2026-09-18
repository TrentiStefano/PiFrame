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
