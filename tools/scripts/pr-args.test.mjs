import test from 'node:test';
import assert from 'node:assert/strict';
import { buildPrCreateArgs, splitArgs } from './pr-args.mjs';

test('verify flags are split from gh arguments, values with spaces stay intact', () => {
  const argv = [
    '--release',
    '--title',
    'fix(ui): Phase 1 safety',
    '--body-file',
    'C:/tmp/body dir/body.md',
    '--no-merge'
  ];
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

test('a leading pnpm "--" separator is not forwarded to gh', () => {
  const argv = ['--', '--base', 'main', '--title', 'fix(ui): Phase 1 safety', '--body-file', 'C:/tmp/body.md'];
  const { verifyArgs, ghArgs } = splitArgs(argv);
  assert.deepEqual(verifyArgs, []);
  assert.deepEqual(ghArgs, ['--base', 'main', '--title', 'fix(ui): Phase 1 safety', '--body-file', 'C:/tmp/body.md']);
  assert.equal(buildPrCreateArgs(ghArgs).includes('--'), false);
});

test('"--" with verify flags: --e2e goes to verify, the separator goes nowhere', () => {
  const argv = ['--', '--e2e', '--title', 'fix(ui): Phase 1 safety'];
  assert.deepEqual(splitArgs(argv), {
    verifyArgs: ['--e2e'],
    ghArgs: ['--title', 'fix(ui): Phase 1 safety']
  });
});

test('"--" with --release and --no-merge, and no gh args, still fills from commits', () => {
  const { verifyArgs, ghArgs } = splitArgs(['--', '--release', '--no-merge']);
  assert.deepEqual(verifyArgs, ['--release', '--no-merge']);
  assert.deepEqual(buildPrCreateArgs(ghArgs), ['pr', 'create', '--base', 'main', '--fill']);
});
