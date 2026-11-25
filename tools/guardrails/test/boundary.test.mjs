import test from 'node:test';
import assert from 'node:assert/strict';
import { checkBoundaries } from '../src/index.mjs';

// In-memory repository files. Expected problems are hand-written, never derived from the code under test.
const file = (path, ...lines) => ({ path, contents: lines.join('\n') });
const lib = (rel) => `apps/pi_frame/lib/${rel}`;
const daemon = (rel) => `apps/agentd/src/${rel}`;

const TABLE = {
  main: ['server', 'remote'],
  remote: ['server'],
  server: ['remote'],
  ui: [],
  sessions: ['ui', 'server'],
  side: ['sessions']
};

const run = (files, { baseline = [], table = TABLE } = {}) =>
  checkBoundaries({ files, daemonAllowedDependencies: table, baseline });
const rules = (result) => result.problems.map((p) => `${p.file} ${p.import} ${p.rule}`);

test('a domain file importing Flutter fails, naming the file, the import, the rule and the fix', () => {
  const result = run([file(lib('domain/session/x.dart'), "import 'package:flutter/material.dart';")]);
  assert.equal(result.ok, false);
  assert.equal(result.problems.length, 1);
  const [problem] = result.problems;
  assert.equal(problem.file, lib('domain/session/x.dart'));
  assert.equal(problem.import, 'package:flutter/material.dart');
  assert.equal(problem.rule, 'domain-flutter');
  assert.match(problem.message, /domain\/ must stay pure Dart/);
});

test('a domain file importing dart:io fails as raw I/O', () => {
  const result = run([file(lib('domain/x.dart'), "import 'dart:io';")]);
  assert.deepEqual(rules(result), [`${lib('domain/x.dart')} dart:io raw-io`]);
});

test('a domain file importing data fails as a layer violation', () => {
  const result = run([file(lib('domain/x.dart'), "import '../data/daemon/pcp_client.dart';")]);
  assert.deepEqual(rules(result), [`${lib('domain/x.dart')} ../data/daemon/pcp_client.dart layer`]);
});

test('a data file importing features, ui or app fails', () => {
  const result = run([
    file(lib('data/a.dart'), "import '../features/chat/chat.dart';"),
    file(lib('data/b.dart'), "import '../ui/card.dart';"),
    file(lib('data/c.dart'), "import '../app/shell.dart';")
  ]);
  assert.deepEqual(rules(result), [
    `${lib('data/a.dart')} ../features/chat/chat.dart layer`,
    `${lib('data/b.dart')} ../ui/card.dart layer`,
    `${lib('data/c.dart')} ../app/shell.dart layer`
  ]);
});

test('a ui file importing features, app or data fails; ui importing domain or the translation tables passes', () => {
  const result = run([
    file(lib('ui/a.dart'), "import '../features/chat/chat.dart';"),
    file(lib('ui/b.dart'), "import '../app/shell.dart';"),
    file(lib('ui/c.dart'), "import '../data/daemon/pcp_client.dart';"),
    file(lib('ui/d.dart'), "import '../domain/session/model.dart';"),
    file(lib('ui/code/e.dart'), "import '../../data/language/strings_shell.dart';")
  ]);
  assert.deepEqual(rules(result), [
    `${lib('ui/a.dart')} ../features/chat/chat.dart layer`,
    `${lib('ui/b.dart')} ../app/shell.dart layer`,
    `${lib('ui/c.dart')} ../data/daemon/pcp_client.dart layer`
  ]);
});

test('a feature file importing raw I/O or a platform plugin fails, whichever it is', () => {
  const imports = [
    "import 'dart:io';",
    "import 'dart:ffi';",
    "import 'package:http/http.dart' as http;",
    "import 'package:ffi/ffi.dart';",
    "import 'package:web_socket_channel/io.dart';",
    "import 'package:win32/win32.dart';",
    "import 'package:url_launcher/url_launcher.dart';",
    "import 'package:file_selector/file_selector.dart';",
    "import 'package:window_manager/window_manager.dart';",
    "import 'package:webview_win_floating/webview.dart';"
  ];
  const result = run(imports.map((line, i) => file(lib(`features/f${i}/x.dart`), line)));
  assert.equal(result.problems.length, imports.length);
  assert.ok(result.problems.every((p) => p.rule === 'raw-io'));
  assert.match(result.problems[0].message, /data\//);
});

test('a feature importing flutter, riverpod or another feature passes', () => {
  const result = run([
    file(lib('features/chat/chat.dart'), "import 'package:flutter/material.dart';", "import '../composer/box.dart';"),
    file(lib('features/composer/box.dart'), "import 'package:flutter_riverpod/flutter_riverpod.dart';")
  ]);
  assert.deepEqual(result, { ok: true, problems: [] });
});

test('harness imported from app or an entry point passes; from any other folder fails', () => {
  const ok = run([
    file(lib('app/shell.dart'), "import '../harness/harness_window.dart';"),
    file(lib('main_harness.dart'), "import 'harness/harness_extensions.dart';")
  ]);
  assert.deepEqual(ok, { ok: true, problems: [] });
  const bad = run([file(lib('features/chat/chat.dart'), "import '../../harness/harness_window.dart';")]);
  assert.deepEqual(rules(bad), [`${lib('features/chat/chat.dart')} ../../harness/harness_window.dart harness`]);
});

test('relative and package:pi_frame imports resolve to the same layer and rule', () => {
  const relative = run([file(lib('data/x.dart'), "import '../features/chat/chat.dart';")]);
  const absolute = run([file(lib('data/x.dart'), "import 'package:pi_frame/features/chat/chat.dart';")]);
  assert.equal(relative.problems.length, 1);
  assert.equal(absolute.problems.length, 1);
  assert.equal(relative.problems[0].rule, 'layer');
  assert.equal(absolute.problems[0].rule, 'layer');
  assert.equal(relative.problems[0].file, absolute.problems[0].file);
});

test('a daemon module cycle fails, naming the loop', () => {
  const result = run([
    file(daemon('remote/r.ts'), "import { s } from '../server/s';"),
    file(daemon('server/s.ts'), "import { r } from '../remote/r';")
  ]);
  assert.equal(result.ok, false);
  assert.equal(result.problems.length, 1);
  const [cycle] = result.problems;
  assert.equal(cycle.rule, 'cycle');
  assert.equal(cycle.import, 'remote -> server -> remote');
  assert.match(cycle.message, /remote -> server -> remote/);
});

test('a daemon module edge missing from the allowed-dependency table fails, including dynamic import()', () => {
  const result = run(
    [
      file(daemon('server/s.ts'), "import { x } from '../ui/x';", "const m = await import('../remote/r');"),
      file(daemon('remote/r.ts'), 'export const r = 1;')
    ],
    { table: { ...TABLE, server: ['remote'] } }
  );
  assert.deepEqual(rules(result), [`${daemon('server/s.ts')} ../ui/x daemon-edge`]);

  const dynamic = run(
    [file(daemon('ui/u.ts'), "const m = await import('../remote/r');"), file(daemon('remote/r.ts'), '')],
    {
      table: { ...TABLE, ui: [] }
    }
  );
  assert.deepEqual(rules(dynamic), [`${daemon('ui/u.ts')} ../remote/r daemon-edge`]);
});

test('a package importing an app fails, from Dart and from TypeScript', () => {
  const result = run([
    file('packages/pi_frame_theme/lib/x.dart', "import 'package:pi_frame/main.dart';"),
    file('packages/pcp-ts/src/x.ts', "import { m } from '../../../apps/agentd/src/main';")
  ]);
  assert.deepEqual(rules(result), [
    'packages/pi_frame_theme/lib/x.dart package:pi_frame/main.dart packages-to-apps',
    'packages/pcp-ts/src/x.ts ../../../apps/agentd/src/main packages-to-apps'
  ]);
});

test('test files are ignored, Dart and TypeScript', () => {
  const result = run([
    file(lib('features/chat/chat_test.dart'), "import 'dart:io';"),
    file(daemon('journal/test/j.test.ts'), "import { r } from '../../remote/r';")
  ]);
  assert.deepEqual(result, { ok: true, problems: [] });
});

test('a baselined violation passes', () => {
  const result = run([file(lib('features/chat/chat.dart'), "import 'dart:io';")], {
    baseline: [{ file: lib('features/chat/chat.dart'), import: 'dart:io' }]
  });
  assert.deepEqual(result, { ok: true, problems: [] });
});

test('a stale baseline entry fails, naming the entry to delete', () => {
  const result = run([file(lib('features/chat/chat.dart'), "import 'package:flutter/material.dart';")], {
    baseline: [{ file: lib('features/gone.dart'), import: 'dart:io' }]
  });
  assert.equal(result.ok, false);
  const stale = result.problems.find((p) => p.rule === 'stale-baseline');
  assert.ok(stale, 'a stale-baseline problem is reported');
  assert.equal(stale.file, lib('features/gone.dart'));
  assert.equal(stale.import, 'dart:io');
  assert.match(stale.message, /delete/);
  assert.match(stale.message, new RegExp(lib('features/gone.dart')));
});

test('a domain file importing flutter_riverpod or riverpod fails: domain/ stays free of state management', () => {
  const result = run([
    file(lib('domain/x.dart'), "import 'package:flutter_riverpod/flutter_riverpod.dart';"),
    file(lib('domain/y.dart'), "import 'package:riverpod/riverpod.dart';")
  ]);
  assert.deepEqual(rules(result), [
    `${lib('domain/x.dart')} package:flutter_riverpod/flutter_riverpod.dart domain-riverpod`,
    `${lib('domain/y.dart')} package:riverpod/riverpod.dart domain-riverpod`
  ]);
});

test('a feature file importing app fails: app/ is the shell, not a library for features', () => {
  const result = run([file(lib('features/workspace/pane.dart'), "import '../../app/row_context_menu.dart';")]);
  assert.deepEqual(rules(result), [`${lib('features/workspace/pane.dart')} ../../app/row_context_menu.dart layer`]);
});
