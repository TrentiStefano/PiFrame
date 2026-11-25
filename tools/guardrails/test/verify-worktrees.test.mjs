import test from 'node:test';
import assert from 'node:assert/strict';
import {
  selectStaleVerifyWorktrees,
  selectLeftoverVerifyFolders,
  leftoverVerifyFailure,
  dirtyVerifyTreeFailure
} from '../src/index.mjs';

const CURRENT = 100;
const folder = (name, overrides = {}) => ({
  name,
  isDirectory: true,
  registered: true,
  linkedToRepo: true,
  repoMarker: true,
  pidAlive: false,
  ...overrides
});
const select = (folders) => selectStaleVerifyWorktrees({ repoName: 'PiFrame', currentPid: CURRENT, folders });

test('selects a registered verify worktree left by an earlier run', () => {
  assert.deepEqual(select([folder('PiFrame-verify-42')]), ['PiFrame-verify-42']);
});

test('selects a removed verify worktree that is still linked to this repository', () => {
  const removed = folder('PiFrame-verify-42', { registered: false, linkedToRepo: true });
  assert.deepEqual(select([removed]), ['PiFrame-verify-42']);
});

test('selects a verify folder whose git link is gone when it still carries this repository marker files', () => {
  const orphan = folder('PiFrame-verify-42', { registered: false, linkedToRepo: false, repoMarker: true });
  assert.deepEqual(select([orphan]), ['PiFrame-verify-42']);
});

test('keeps a folder with no .git and no repository marker: nothing positively says it is a verify worktree', () => {
  const bare = folder('PiFrame-verify-42', { registered: false, linkedToRepo: false, repoMarker: false });
  assert.deepEqual(select([bare]), []);
});

test('keeps the folder of the current run', () => {
  assert.deepEqual(select([folder(`PiFrame-verify-${CURRENT}`)]), []);
});

test('keeps unrelated folders, including other repositories and other verify-like names', () => {
  const kept = [
    'PiFrame',
    'PiFrame-releasefix-verify-26536',
    'OtherRepo-verify-42',
    'PiFrame-verify-42-backup',
    'PiFrame-verify-abc'
  ].map((name) => folder(name));
  assert.deepEqual(select(kept), []);
});

test('keeps a verify-named folder that is not a worktree of this repository', () => {
  const foreign = folder('PiFrame-verify-42', { registered: false, linkedToRepo: false, repoMarker: false });
  assert.deepEqual(select([foreign]), []);
});

test('keeps a verify folder whose run is still alive', () => {
  assert.deepEqual(select([folder('PiFrame-verify-42', { pidAlive: true })]), []);
});

test('keeps files that are not directories', () => {
  assert.deepEqual(select([folder('PiFrame-verify-42', { isDirectory: false })]), []);
});

test('selects only the stale ones from a mixed listing, in the order given', () => {
  const listing = [
    folder('PiFrame-verify-7'),
    folder(`PiFrame-verify-${CURRENT}`),
    folder('PiFrame-verify-9', { pidAlive: true }),
    folder('PiFrame-releasefix-verify-26536'),
    folder('PiFrame-verify-11', { registered: false, linkedToRepo: false, repoMarker: false }),
    folder('PiFrame-verify-13')
  ];
  assert.deepEqual(select(listing), ['PiFrame-verify-7', 'PiFrame-verify-13']);
});

test('no leftover folders gives no failure message', () => {
  assert.equal(leftoverVerifyFailure({ leftovers: [] }), null);
});

test('leftover folders fail loudly, naming every folder left behind', () => {
  const message = leftoverVerifyFailure({
    leftovers: ['C:/Personale/Repos/PiFrame-verify-42', 'C:/Personale/Repos/PiFrame-verify-43']
  });
  assert.match(message, /2 verify worktree folder\(s\) left behind/);
  assert.match(message, /PiFrame-verify-42/);
  assert.match(message, /PiFrame-verify-43/);
  assert.match(message, /Delete them by hand/);
});

test('a clean verification worktree gives no failure', () => {
  assert.equal(dirtyVerifyTreeFailure({ dirtyFiles: [] }), null);
});

test('a dirty verification worktree fails loudly, naming every dirty file', () => {
  const message = dirtyVerifyTreeFailure({
    dirtyFiles: [' M docs/design-evidence/a.png', '?? website/assets/b.png']
  });
  assert.match(message, /2 file\(s\) changed/);
  assert.match(message, /docs\/design-evidence\/a\.png/);
  assert.match(message, /website\/assets\/b\.png/);
  assert.match(message, /git checkout/);
});

const leftovers = (folders) => selectLeftoverVerifyFolders({ repoName: 'PiFrame', currentPid: CURRENT, folders });

test('leftover: this run folder counts when it is still there', () => {
  const ours = folder(`PiFrame-verify-${CURRENT}`, { pidAlive: true });
  assert.deepEqual(leftovers([ours]), [`PiFrame-verify-${CURRENT}`]);
});

test('leftover: another live run folder does not count (it belongs to a verify still running)', () => {
  assert.deepEqual(leftovers([folder('PiFrame-verify-42', { pidAlive: true })]), []);
});

test('leftover: a stale confirmed folder that survived cleanup counts', () => {
  assert.deepEqual(leftovers([folder('PiFrame-verify-42')]), ['PiFrame-verify-42']);
});

test('leftover: a stale folder that is not ours does not count', () => {
  const foreign = folder('PiFrame-verify-42', { registered: false, linkedToRepo: false, repoMarker: false });
  assert.deepEqual(leftovers([foreign]), []);
});
