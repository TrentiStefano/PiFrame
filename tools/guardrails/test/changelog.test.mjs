import test from 'node:test';
import assert from 'node:assert/strict';
import { syncChangelog } from '../src/index.mjs';

const ROOT = '# Changelog\n\n## [1.5.1](https://example.test) (2026-11-01)\n\n* fix a thing\n';
const STALE = '# Changelog\n\n## [1.4.0](https://example.test) (2026-09-01)\n\n* older\n';
const FIX = 'node tools/scripts/sync-changelog.mjs';

test('check mode fails on a missing asset and names the command that generates it', () => {
  const result = syncChangelog({ root: ROOT, asset: null, mode: 'check' });
  assert.equal(result.status, 'fail');
  assert.equal(result.content, undefined, 'check mode must never hand back content to write');
  assert.match(result.message, /missing/);
  assert.ok(result.message.includes(FIX), result.message);
});

test('check mode fails on a stale asset (drift) and never returns content to write', () => {
  const result = syncChangelog({ root: ROOT, asset: STALE, mode: 'check' });
  assert.equal(result.status, 'fail');
  assert.equal(result.content, undefined);
  assert.match(result.message, /stale/);
  assert.ok(result.message.includes(FIX), result.message);
});

test('check mode passes when the asset is an exact copy of the root changelog', () => {
  assert.equal(syncChangelog({ root: ROOT, asset: ROOT, mode: 'check' }).status, 'ok');
});

test('a copy that differs only in line endings is drift: the asset must be byte-identical', () => {
  assert.equal(syncChangelog({ root: ROOT, asset: ROOT.replace(/\n/g, '\r\n'), mode: 'check' }).status, 'fail');
});

test('write mode generates a missing or stale asset from the root changelog', () => {
  for (const asset of [null, STALE]) {
    const result = syncChangelog({ root: ROOT, asset, mode: 'write' });
    assert.equal(result.status, 'write');
    assert.equal(result.content, ROOT);
  }
});

test('write mode leaves an up-to-date asset alone', () => {
  const result = syncChangelog({ root: ROOT, asset: ROOT, mode: 'write' });
  assert.equal(result.status, 'ok');
  assert.equal(result.content, undefined);
});

test('an unknown mode is an error that names the known modes, so a typo cannot skip the check', () => {
  assert.throws(() => syncChangelog({ root: ROOT, asset: ROOT, mode: 'fix' }), /write.*check/);
});
