import test from 'node:test';
import assert from 'node:assert/strict';
import { buildPrCreateArgs, prBodyText, splitArgs } from './pr-args.mjs';

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

test('gh pr create never fills the body from the commits: the body comes from the PR template', () => {
  assert.deepEqual(buildPrCreateArgs([]), ['pr', 'create', '--base', 'main']);
  assert.equal(buildPrCreateArgs(['--title', 'fix(ui): x']).includes('--fill'), false);
});

test('the body is the --body value, or the text of --body-file, in either spelling', () => {
  const files = { 'body.md': '## Summary\nx' };
  const read = (path) => files[path];
  assert.equal(prBodyText(['--title', 't', '--body', 'inline text'], read), 'inline text');
  assert.equal(prBodyText(['--body-file', 'body.md'], read), '## Summary\nx');
  assert.equal(prBodyText(['--body=inline'], read), 'inline');
  assert.equal(prBodyText(['--body-file=body.md'], read), '## Summary\nx');
});

test('no body flag gives no body, so open-pr refuses before it creates anything', () => {
  assert.equal(
    prBodyText(['--title', 't', '--fill'], () => ''),
    undefined
  );
  assert.equal(
    prBodyText([], () => ''),
    undefined
  );
});

test('a --body given without text is an empty body, not a missing one', () => {
  assert.equal(
    prBodyText(['--body', ''], () => ''),
    ''
  );
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

test('"--" with --release and --no-merge, and no gh args, gives no body (refused before creation)', () => {
  const { verifyArgs, ghArgs } = splitArgs(['--', '--release', '--no-merge']);
  assert.deepEqual(verifyArgs, ['--release', '--no-merge']);
  assert.equal(
    prBodyText(ghArgs, () => ''),
    undefined
  );
});
