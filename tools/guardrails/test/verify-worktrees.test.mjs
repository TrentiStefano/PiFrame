import test from 'node:test';
import assert from 'node:assert/strict';
import { selectStaleVerifyWorktrees, leftoverVerifyFailure } from '../src/index.mjs';

const CURRENT = 100;
const folder = (name, overrides = {}) => ({
  name,
  isDirectory: true,
  registered: true,
  linkedToRepo: true,
  gitEntry: true,
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

test('selects a verify folder whose git link is gone (a failed removal left only its content)', () => {
  const orphan = folder('PiFrame-verify-42', { registered: false, linkedToRepo: false, gitEntry: false });
  assert.deepEqual(select([orphan]), ['PiFrame-verify-42']);
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
  const foreign = folder('PiFrame-verify-42', { registered: false, linkedToRepo: false });
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
    folder('PiFrame-verify-11', { registered: false, linkedToRepo: false }),
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
