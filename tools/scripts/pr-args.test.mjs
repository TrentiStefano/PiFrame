import test from 'node:test';
import assert from 'node:assert/strict';
import { buildPrCreateArgs, splitArgs } from './pr-args.mjs';

test('verify flags are split from gh arguments, values with spaces stay intact', () => {
  const argv = ['--release', '--title', 'fix(ui): Phase 1 safety', '--body-file', 'C:/tmp/body dir/body.md', '--no-merge'];
  assert.deepEqual(splitArgs(argv), {
    verifyArgs: ['--release', '--no-merge'],
    ghArgs: ['--title', 'fix(ui): Phase 1 safety', '--body-file', 'C:/tmp/body dir/body.md']
  });
});

test('gh args with title and body-file are passed through unchanged, without --fill', () => {
  const ghArgs = ['--title', 'fix(ui): Phase 1 safety', '--body-file', 'C:/tmp/body dir/body.md'];
  assert.deepEqual(buildPrCreateArgs(ghArgs), ['pr', 'create', '--base', 'main', ...ghArgs]);
});

test('without content flags, gh pr create fills from the commits', () => {
  assert.deepEqual(buildPrCreateArgs([]), ['pr', 'create', '--base', 'main', '--fill']);
});
