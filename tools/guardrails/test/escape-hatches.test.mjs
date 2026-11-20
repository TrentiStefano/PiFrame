import test from 'node:test';
import assert from 'node:assert/strict';
import { auditEscapeHatches } from '../src/index.mjs';

const PACKAGES = ['agentd', 'pcp-ts', 'pcp-spec', 'pi_frame', 'pi_frame_protocol', 'pi_frame_theme', 'tools', 'e2e'];
const PATTERNS = [
  '// ignore:',
  '// ignore_for_file:',
  '@ts-ignore',
  '@ts-expect-error',
  '@ts-nocheck',
  'eslint-disable',
  'as any',
  ': any',
  'as unknown as',
  '// coverage:ignore'
];

const file = (path, ...lines) => ({ path, contents: lines.join('\n') });
const zeros = () => Object.fromEntries(PATTERNS.map((p) => [p, 0]));
/** A baseline with every package and pattern at zero, then the given `[package, kind, pattern, count]` overrides. */
function baseline(...entries) {
  const b = Object.fromEntries(PACKAGES.map((p) => [p, { lib: zeros(), test: zeros() }]));
  for (const [pkg, kind, pattern, count] of entries) b[pkg][kind][pattern] = count;
  return b;
}

test('counts every package x lib/test x pattern, listing zeros explicitly', () => {
  const { counts } = auditEscapeHatches({ files: [], baseline: baseline() });
  assert.deepEqual(Object.keys(counts), PACKAGES);
  for (const pkg of PACKAGES) {
    assert.deepEqual(Object.keys(counts[pkg]), ['lib', 'test']);
    assert.deepEqual(counts[pkg].lib, zeros());
    assert.deepEqual(counts[pkg].test, zeros());
  }
});

test('detects every pattern, each occurrence counted, in the package the file belongs to', () => {
  const files = [
    file(
      'apps/agentd/src/a.ts',
      '// @ts-ignore',
      '// @ts-expect-error broken upstream type',
      '// @ts-nocheck',
      '// eslint-disable-next-line no-console',
      'const x = y as any as any;',
      'function f(a: any, b:any[]) {}',
      'const z = w as unknown as Foo;',
      '/* coverage:ignore-start */ // coverage:ignore-line'
    ),
    file(
      'apps/pi_frame/lib/a.dart',
      '// ignore_for_file: deprecated_member_use',
      'foo(); // ignore: avoid_print',
      '  // ignore: deprecated_member_use',
      '// coverage:ignore-file'
    )
  ];
  const { counts } = auditEscapeHatches({ files, baseline: baseline() });
  assert.deepEqual(counts.agentd.lib, {
    ...zeros(),
    '@ts-ignore': 1,
    '@ts-expect-error': 1,
    '@ts-nocheck': 1,
    'eslint-disable': 1,
    'as any': 2,
    ': any': 2,
    'as unknown as': 1,
    '// coverage:ignore': 2
  });
  assert.deepEqual(counts.pi_frame.lib, {
    ...zeros(),
    '// ignore:': 2,
    '// ignore_for_file:': 1,
    '// coverage:ignore': 1
  });
});

test('maps each package directory and ignores files outside the packages', () => {
  const hatch = 'let a = b as any;';
  const files = [
    file('apps/agentd/src/x.ts', hatch),
    file('packages/pcp-ts/src/x.ts', hatch),
    file('packages/pcp-spec/test/validate.js', hatch),
    file('tools/scripts/x.mjs', hatch),
    file('test/e2e/src/helpers.ts', hatch),
    file('website/js/site.js', hatch),
    file('brag-output/render.mjs', hatch),
    file('apps/pi_frame/lib/x.dart', '// ignore: x'),
    file('packages/pi_frame_protocol/lib/x.dart', '// ignore: x'),
    file('packages/pi_frame_theme/lib/x.dart', '// ignore: x')
  ];
  const { counts } = auditEscapeHatches({ files, baseline: baseline() });
  const total = (pkg, pattern) => counts[pkg].lib[pattern] + counts[pkg].test[pattern];
  for (const pkg of ['agentd', 'pcp-ts', 'pcp-spec', 'tools', 'e2e']) assert.equal(total(pkg, 'as any'), 1, pkg);
  for (const pkg of ['pi_frame', 'pi_frame_protocol', 'pi_frame_theme']) assert.equal(total(pkg, '// ignore:'), 1, pkg);
});

test('classifies test code by test folder and by _test.dart / .test.ts / .test.mjs / .spec.ts naming', () => {
  const hatch = 'x as any;';
  const files = [
    file('apps/agentd/src/commands/test/Dispatcher.test.ts', hatch),
    file('apps/agentd/src/remote/helper.test.ts', hatch),
    file('apps/agentd/src/commands/test/fixtures.ts', hatch),
    file('apps/agentd/src/commands/Dispatcher.ts', hatch),
    file('tools/scripts/pr-args.test.mjs', hatch),
    file('tools/scripts/pr-args.mjs', hatch),
    file('test/e2e/src/fault_injection.spec.ts', hatch),
    file('apps/pi_frame/test/helpers/fake.dart', '// ignore: x'),
    file('apps/pi_frame/lib/foo_test.dart', '// ignore: x'),
    file('apps/pi_frame/lib/testing_tools.dart', '// ignore: x')
  ];
  const { counts } = auditEscapeHatches({ files, baseline: baseline() });
  assert.equal(counts.agentd.test['as any'], 3);
  assert.equal(counts.agentd.lib['as any'], 1);
  assert.equal(counts.tools.test['as any'], 1);
  assert.equal(counts.tools.lib['as any'], 1);
  assert.equal(counts.e2e.test['as any'], 1);
  assert.equal(counts.pi_frame.test['// ignore:'], 2);
  assert.equal(counts.pi_frame.lib['// ignore:'], 1);
});

test('ignores build, dist and dependency folders', () => {
  const hatch = 'x as any; // ignore: y';
  const files = [
    'apps/agentd/node_modules/pkg/index.ts',
    'apps/agentd/dist/index.js',
    'apps/agentd/build/out.js',
    'apps/pi_frame/build/web/main.dart',
    'apps/pi_frame/.dart_tool/x.dart',
    'tools/scripts/coverage/lcov.js',
    'packages/pcp-ts/out/index.js'
  ].map((p) => file(p, hatch));
  const { counts, mismatches } = auditEscapeHatches({ files, baseline: baseline() });
  assert.deepEqual(mismatches, []);
  assert.deepEqual(counts.agentd.lib, zeros());
});

test('Dart-only patterns are counted in Dart, TypeScript-only patterns in TypeScript and JavaScript', () => {
  const files = [
    file('apps/pi_frame/lib/grip.dart', '// A 2 px grip: any radius works.', 'when(() => f(x: any()));'),
    file('apps/agentd/src/a.ts', "const s = '// ignore: not dart';")
  ];
  const { counts } = auditEscapeHatches({ files, baseline: baseline() });
  assert.deepEqual(counts.pi_frame.lib, zeros());
  assert.deepEqual(counts.agentd.lib, zeros());
});

test('"as any" and ": any" count only in type positions, not in prose', () => {
  const files = [
    file(
      'apps/agentd/src/prose.ts',
      '// It blocks the obvious ways: any `gh` call, and treats it as any other command.',
      '/** Note: any value works here. */'
    ),
    file(
      'apps/agentd/src/types.ts',
      'let a: any;',
      'f(b as any);',
      'const c = (d as any).e;',
      'function g(h: any, i?: any[]): any {',
      'const j = k as any as L;',
      'type M = { n: any };',
      'let o: any = p as any',
      'let q: any | undefined; // trailing'
    )
  ];
  const { counts } = auditEscapeHatches({ files, baseline: baseline() });
  assert.equal(counts.agentd.lib['as any'], 4);
  assert.equal(counts.agentd.lib[': any'], 7);
});

test('the audit does not count its own pattern definitions and fixtures', () => {
  const files = [
    file('tools/guardrails/src/escape-hatches.mjs', "const p = 'as any';"),
    file('tools/guardrails/test/escape-hatches.test.mjs', 'x as any;')
  ];
  const { counts } = auditEscapeHatches({ files, baseline: baseline() });
  assert.deepEqual(counts.tools, { lib: zeros(), test: zeros() });
});

test('a tree that matches the baseline passes', () => {
  const files = [file('apps/agentd/src/a.ts', 'x as any;'), file('apps/pi_frame/test/a_test.dart', '// ignore: y')];
  const result = auditEscapeHatches({
    files,
    baseline: baseline(['agentd', 'lib', 'as any', 1], ['pi_frame', 'test', '// ignore:', 1])
  });
  assert.deepEqual(result.mismatches, []);
  assert.equal(result.ok, true);
});

test('a new escape hatch fails, naming the file, the line, the pattern and how to fix the root cause', () => {
  const files = [file('apps/agentd/src/old.ts', 'a as any;'), file('apps/agentd/src/new.ts', 'ok();', 'b as any;')];
  const result = auditEscapeHatches({
    files,
    baseline: baseline(['agentd', 'lib', 'as any', 1]),
    changedPaths: ['apps/agentd/src/new.ts']
  });
  assert.equal(result.ok, false);
  assert.equal(result.mismatches.length, 1);
  const [m] = result.mismatches;
  assert.deepEqual(
    { package: m.package, kind: m.kind, pattern: m.pattern, baseline: m.baseline, actual: m.actual },
    { package: 'agentd', kind: 'lib', pattern: 'as any', baseline: 1, actual: 2 }
  );
  assert.match(m.message, /agentd lib "as any": 1 → 2/);
  assert.match(m.message, /apps\/agentd\/src\/new\.ts:2 \(changed\)/);
  assert.match(m.message, /apps\/agentd\/src\/old\.ts:1/);
  // Changed files come first: they are the likely culprits.
  assert.ok(m.message.indexOf('new.ts') < m.message.indexOf('old.ts'));
  assert.match(m.message, /real type/);
  assert.match(m.message, /unknown/);
  assert.match(m.message, /Do not raise the baseline/);
  assert.match(m.message, /human-approved/);
});

test('every pattern has its own root-cause fix text', () => {
  const lines = {
    '// ignore:': ['apps/pi_frame/lib/a.dart', '// ignore: x', /analyzer/],
    '// ignore_for_file:': ['apps/pi_frame/lib/a.dart', '// ignore_for_file: x', /analyzer/],
    '@ts-ignore': ['apps/agentd/src/a.ts', '// @ts-ignore', /type error/],
    '@ts-expect-error': ['apps/agentd/src/a.ts', '// @ts-expect-error', /type error/],
    '@ts-nocheck': ['apps/agentd/src/a.ts', '// @ts-nocheck', /type error/],
    'eslint-disable': ['apps/agentd/src/a.ts', '// eslint-disable-line', /ESLint is not installed/],
    'as any': ['apps/agentd/src/a.ts', 'x as any;', /real type/],
    ': any': ['apps/agentd/src/a.ts', 'let x: any;', /real type/],
    'as unknown as': ['apps/agentd/src/a.ts', 'x as unknown as Y;', /real type/],
    '// coverage:ignore': ['apps/agentd/src/a.ts', '// coverage:ignore-line', /test that covers/]
  };
  for (const [pattern, [path, line, fix]] of Object.entries(lines)) {
    const { mismatches } = auditEscapeHatches({ files: [file(path, line)], baseline: baseline() });
    assert.equal(mismatches.length, 1, pattern);
    assert.equal(mismatches[0].pattern, pattern);
    assert.match(mismatches[0].message, fix, pattern);
  }
});

test('a removed escape hatch fails until the baseline is lowered, showing the exact baseline edit', () => {
  const files = [file('apps/agentd/src/commands/test/x.test.ts', 'a as any;')];
  const result = auditEscapeHatches({ files, baseline: baseline(['agentd', 'test', 'as any', 3]) });
  assert.equal(result.ok, false);
  const [m] = result.mismatches;
  assert.deepEqual([m.package, m.kind, m.pattern, m.baseline, m.actual], ['agentd', 'test', 'as any', 3, 1]);
  assert.match(m.message, /agentd test "as any": 3 → 1/);
  assert.match(m.message, /tools\/guardrails\/escape-hatch-baseline\.json/);
  assert.match(m.message, /"agentd" → "test": change "as any": 3 to "as any": 1/);
});

test('moving an escape hatch between files of the same package passes', () => {
  const before = auditEscapeHatches({
    files: [file('apps/agentd/src/a.ts', 'x as any;'), file('apps/agentd/src/b.ts', 'ok();')],
    baseline: baseline(['agentd', 'lib', 'as any', 1])
  });
  const after = auditEscapeHatches({
    files: [file('apps/agentd/src/a.ts', 'ok();'), file('apps/agentd/src/sub/b.ts', 'x as any;')],
    baseline: baseline(['agentd', 'lib', 'as any', 1])
  });
  assert.deepEqual(before.mismatches, []);
  assert.deepEqual(after.mismatches, []);
});

test('a baseline that leaves out a package or pattern fails, so every entry stays explicit', () => {
  const incomplete = baseline();
  delete incomplete.e2e;
  delete incomplete.agentd.test['as any'];
  const { mismatches } = auditEscapeHatches({ files: [], baseline: incomplete });
  const missing = mismatches.map((m) => `${m.package} ${m.kind} ${m.pattern}`);
  assert.ok(missing.includes('agentd test as any'));
  assert.ok(missing.includes('e2e lib : any'));
  assert.equal(missing.length, 1 + 2 * PATTERNS.length);
  assert.match(mismatches[0].message, /no entry/);
  assert.match(mismatches[0].message, /"as any": 0/);
});

test('a baseline entry the audit does not know fails instead of being ignored', () => {
  const extra = baseline();
  extra.website = { lib: zeros(), test: zeros() };
  extra.agentd.lib['as never'] = 2;
  const { mismatches } = auditEscapeHatches({ files: [], baseline: extra });
  assert.equal(mismatches.length, 2);
  assert.ok(mismatches.every((m) => /unknown/.test(m.message) && /Remove/.test(m.message)));
});
