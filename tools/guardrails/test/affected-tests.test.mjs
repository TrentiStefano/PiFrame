import test from 'node:test';
import assert from 'node:assert/strict';
import { affectedDartTests } from '../src/index.mjs';

const projects = [
  { dir: 'packages/pi_frame_theme', package: 'pi_frame_theme' },
  { dir: 'apps/pi_frame', package: 'pi_frame' }
];
const dart = (path, ...imports) => ({ path, contents: imports.map((i) => `import '${i}';`).join('\n') });

const files = [
  dart('apps/pi_frame/lib/data/daemon/daemon_providers.dart', 'dart:async', 'pcp_client.dart'),
  dart('apps/pi_frame/lib/data/daemon/pcp_client.dart', 'package:http/http.dart'),
  dart('apps/pi_frame/lib/app/shell.dart', '../data/daemon/daemon_providers.dart'),
  dart('apps/pi_frame/lib/ui/button.dart', 'package:pi_frame_theme/pi_frame_theme.dart'),
  dart('packages/pi_frame_theme/lib/pi_frame_theme.dart', 'src/tokens.dart'),
  dart('packages/pi_frame_theme/lib/src/tokens.dart'),
  dart('packages/pi_frame_theme/test/tokens_test.dart', 'package:pi_frame_theme/src/tokens.dart'),
  // Regression for #116: a test that reaches a changed file only through the app shell must still run.
  dart('apps/pi_frame/test/showcase_test.dart', 'package:pi_frame/app/shell.dart'),
  dart('apps/pi_frame/test/session_defaults_test.dart', 'package:pi_frame/data/daemon/daemon_providers.dart'),
  dart('apps/pi_frame/test/button_test.dart', 'package:pi_frame/ui/button.dart', 'helpers/pump.dart'),
  dart('apps/pi_frame/test/helpers/pump.dart')
];

test('a changed file selects every test that imports it, directly or through other files', () => {
  const result = affectedDartTests({
    files,
    projects,
    changed: ['apps/pi_frame/lib/data/daemon/daemon_providers.dart']
  });
  assert.deepEqual(result, {
    'apps/pi_frame': ['test/session_defaults_test.dart', 'test/showcase_test.dart']
  });
});

test('imports across packages and relative imports inside lib are followed', () => {
  const result = affectedDartTests({ files, projects, changed: ['packages/pi_frame_theme/lib/src/tokens.dart'] });
  assert.deepEqual(result, {
    'packages/pi_frame_theme': ['test/tokens_test.dart'],
    'apps/pi_frame': ['test/button_test.dart']
  });
});

test('a changed test helper selects the tests that import it, and a changed test selects itself', () => {
  const result = affectedDartTests({
    files,
    projects,
    changed: ['apps/pi_frame/test/helpers/pump.dart', 'packages/pi_frame_theme/test/tokens_test.dart']
  });
  assert.deepEqual(result, {
    'packages/pi_frame_theme': ['test/tokens_test.dart'],
    'apps/pi_frame': ['test/button_test.dart']
  });
});

test('changes outside Dart sources select no tests', () => {
  assert.deepEqual(affectedDartTests({ files, projects, changed: ['README.md', 'apps/agentd/src/main.ts'] }), {});
});
