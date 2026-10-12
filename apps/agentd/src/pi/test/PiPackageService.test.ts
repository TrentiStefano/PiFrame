import test from 'node:test';
import * as assert from 'node:assert/strict';
import {
  parsePiListOutput,
  pinnedNpmSource,
  pinnedNpmVersion,
} from '../PiPackageService.js';

test('package list parser returns personal packages and ignores project scope', () => {
  const packages = parsePiListOutput(`User packages:
  npm:pi-caveman
    C:\\Users\\user\\.pi\\agent\\npm\\node_modules\\pi-caveman
  npm:@scope/tools@1.2.3
    C:\\Users\\user\\.pi\\agent\\npm\\node_modules\\@scope\\tools
Project packages:
  ./local-package
    C:\\repo\\local-package
`);
  assert.deepEqual(packages, [
    {
      source: 'npm:pi-caveman',
      installPath: 'C:\\Users\\user\\.pi\\agent\\npm\\node_modules\\pi-caveman',
      scope: 'user',
    },
    {
      source: 'npm:@scope/tools@1.2.3',
      installPath: 'C:\\Users\\user\\.pi\\agent\\npm\\node_modules\\@scope\\tools',
      scope: 'user',
    },
  ]);
  assert.equal(pinnedNpmVersion('npm:@scope/tools@1.2.3'), '1.2.3');
  assert.equal(pinnedNpmVersion('npm:pi-caveman'), null);
});

test('pin creates an exact npm source and rejects invalid specs', () => {
  assert.equal(
    pinnedNpmSource('npm:@scope/tools', 'v2.4.0'),
    'npm:@scope/tools@2.4.0',
  );
  assert.throws(() => pinnedNpmSource('git:github.com/a/b', '2.4.0'));
  assert.throws(() => pinnedNpmSource('npm:tools', 'latest; delete files'));
});
