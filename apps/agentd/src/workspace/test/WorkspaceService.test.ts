import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { execFileSync } from 'node:child_process';
import { WorkspaceService } from '../WorkspaceService.js';

function createRepo(): { root: string; cleanup: () => void } {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-workspace-test-'));
  const git = (args: string[]) => execFileSync('git', args, { cwd: root, stdio: 'ignore' });
  git(['init', '-q']);
  git(['config', 'user.email', 'test@example.com']);
  git(['config', 'user.name', 'PiFrame Test']);
  git(['config', 'core.autocrlf', 'false']);
  fs.writeFileSync(path.join(root, 'file.txt'), 'initial\n');
  git(['add', 'file.txt']);
  git(['commit', '-qm', 'initial']);
  return { root, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

test('WorkspaceService reads text, reports SHA-256 revision, and rejects stale saves', async () => {
  const repo = createRepo();
  try {
    const service = new WorkspaceService();
    const read = await service.readFile(repo.root, 'file.txt');
    assert.equal(read.content, 'initial\n');
    assert.match(read.revision, /^[a-f0-9]{64}$/);
    const saved = await service.saveFile(repo.root, 'file.txt', 'updated\n', read.revision);
    assert.match(saved.revision, /^[a-f0-9]{64}$/);
    await assert.rejects(service.saveFile(repo.root, 'file.txt', 'stale\n', read.revision), { code: 'WORKSPACE_REVISION_CONFLICT' });
    assert.equal(fs.readFileSync(path.join(repo.root, 'file.txt'), 'utf8'), 'updated\n');
  } finally {
    repo.cleanup();
  }
});

test('WorkspaceService rejects traversal and symlink escapes, lists repository-relative files', async () => {
  const repo = createRepo();
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-workspace-outside-'));
  try {
    fs.writeFileSync(path.join(outside, 'secret.txt'), 'secret');
    fs.symlinkSync(outside, path.join(repo.root, 'outside-link'), 'junction');
    const service = new WorkspaceService();
    await assert.rejects(service.readFile(repo.root, '../secret.txt'), { code: 'WORKSPACE_PATH_INVALID' });
    await assert.rejects(service.readFile(repo.root, 'outside-link/secret.txt'), { code: 'WORKSPACE_PATH_INVALID' });
    const listing = await service.listFiles(repo.root);
    assert.equal(listing.rootPath, fs.realpathSync(repo.root));
    assert.ok(listing.files.some((file) => file.path === 'file.txt'));
    assert.ok(!listing.files.some((file) => file.path.startsWith('outside-link/')));
  } finally {
    fs.rmSync(outside, { recursive: true, force: true });
    repo.cleanup();
  }
});

test('WorkspaceService lists tracked and non-ignored repository files, not dependency trees', async () => {
  const repo = createRepo();
  try {
    fs.writeFileSync(path.join(repo.root, '.gitignore'), 'ignored/\n');
    fs.mkdirSync(path.join(repo.root, 'ignored'));
    fs.writeFileSync(path.join(repo.root, 'ignored', 'dependency.txt'), 'ignore me');
    const service = new WorkspaceService();
    const listing = await service.listFiles(repo.root);
    assert.ok(listing.files.some((file) => file.path === 'file.txt'));
    assert.ok(listing.files.some((file) => file.path === '.gitignore'));
    assert.ok(!listing.files.some((file) => file.path.startsWith('ignored/')));
    assert.equal(listing.truncated, false);
  } finally {
    repo.cleanup();
  }
});

test('WorkspaceService discards a staged new file without leaving it in the index or worktree', async () => {
  const repo = createRepo();
  try {
    const service = new WorkspaceService();
    fs.writeFileSync(path.join(repo.root, 'new.txt'), 'new file');
    await service.gitAction(repo.root, 'stage', ['new.txt']);
    assert.equal((await service.getStatus(repo.root, true)).files.find((file) => file.path === 'new.txt')?.staged, true);
    const result = await service.gitAction(repo.root, 'discard', ['new.txt']);
    assert.equal(fs.existsSync(path.join(repo.root, 'new.txt')), false);
    assert.ok(!result.status.files.some((file) => file.path === 'new.txt'));
  } finally {
    repo.cleanup();
  }
});

test('WorkspaceService stage, unstage, commit exact staged set, discard, and reject stale Git selections', async () => {
  const repo = createRepo();
  try {
    const service = new WorkspaceService();
    fs.writeFileSync(path.join(repo.root, 'file.txt'), 'changed\n');
    const staged = await service.gitAction(repo.root, 'stage', ['file.txt']);
    assert.equal(staged.status.files.find((file) => file.path === 'file.txt')?.staged, true);
    await service.gitAction(repo.root, 'unstage', ['file.txt']);
    assert.equal((await service.getStatus(repo.root, true)).files.find((file) => file.path === 'file.txt')?.staged, false);

    await service.gitAction(repo.root, 'stage', ['file.txt']);
    fs.writeFileSync(path.join(repo.root, 'another.txt'), 'untracked');
    await service.gitAction(repo.root, 'stage', ['another.txt']);
    await assert.rejects(
      service.gitAction(repo.root, 'commit', ['file.txt'], ['file.txt'], 'should not commit'),
      { code: 'WORKSPACE_STAGED_SET_MISMATCH' }
    );
    await service.gitAction(repo.root, 'unstage', ['another.txt']);
    await service.gitAction(repo.root, 'commit', ['file.txt'], ['file.txt'], 'save file');
    assert.equal((await service.getStatus(repo.root, true)).files.length, 1);

    fs.writeFileSync(path.join(repo.root, 'file.txt'), 'discard me');
    fs.writeFileSync(path.join(repo.root, 'untracked.txt'), 'remove me');
    const discarded = await service.gitAction(repo.root, 'discard', ['file.txt', 'untracked.txt', 'another.txt']);
    assert.equal(fs.readFileSync(path.join(repo.root, 'file.txt'), 'utf8'), 'changed\n');
    assert.equal(fs.existsSync(path.join(repo.root, 'untracked.txt')), false);
    assert.equal(discarded.status.files.length, 0);

    await assert.rejects(service.gitAction(repo.root, 'stage', ['missing.txt']), { code: 'WORKSPACE_STALE_STATUS' });
  } finally {
    repo.cleanup();
  }
});

test('WorkspaceService rejects binary and oversized files explicitly', async () => {
  const repo = createRepo();
  try {
    fs.writeFileSync(path.join(repo.root, 'binary.bin'), Buffer.from([0, 1, 2]));
    fs.writeFileSync(path.join(repo.root, 'large.txt'), Buffer.alloc(1024 * 1024 + 1, 65));
    const service = new WorkspaceService();
    await assert.rejects(service.readFile(repo.root, 'binary.bin'), { code: 'WORKSPACE_UNSUPPORTED_FILE' });
    await assert.rejects(service.readFile(repo.root, 'large.txt'), { code: 'WORKSPACE_FILE_TOO_LARGE' });
  } finally {
    repo.cleanup();
  }
});
