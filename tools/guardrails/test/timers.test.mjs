import test from 'node:test';
import assert from 'node:assert/strict';
import { checkTimers } from '../src/index.mjs';

const dart = (...lines) => ({ path: 'apps/pi_frame/lib/a/widget.dart', contents: lines.join('\n') });
const ts = (...lines) => ({ path: 'apps/agentd/src/a/thing.ts', contents: lines.join('\n') });
const rules = (result) => result.problems.map((p) => p.line);

test('a Dart Timer with a literal duration fails, naming the file and line', () => {
  const result = checkTimers({ files: [dart('void f() {', '  _t = Timer(const Duration(seconds: 5), () {});', '}')] });
  assert.equal(result.ok, false);
  assert.equal(result.problems.length, 1);
  assert.equal(result.problems[0].path, 'apps/pi_frame/lib/a/widget.dart');
  assert.equal(result.problems[0].line, 2);
  assert.match(result.problems[0].message, /named constant/);
});

test('a Dart Timer.periodic with a literal duration fails', () => {
  const result = checkTimers({ files: [dart('_t = Timer.periodic(const Duration(seconds: 1), (_) {});')] });
  assert.equal(result.ok, false);
  assert.deepEqual(rules(result), [1]);
});

test('a Dart Future.delayed with a literal duration fails', () => {
  const result = checkTimers({ files: [dart('await Future.delayed(const Duration(seconds: 3));')] });
  assert.equal(result.ok, false);
  assert.deepEqual(rules(result), [1]);
});

test('a multi-line Dart call with a literal duration fails on the line of the literal', () => {
  const result = checkTimers({
    files: [dart('_t = Timer(', '  const Duration(milliseconds: 250),', '  () {},', ');')]
  });
  assert.equal(result.ok, false);
  assert.deepEqual(rules(result), [1]);
});

test('a Dart timer with a named constant or a variable passes', () => {
  const result = checkTimers({
    files: [
      dart(
        '_t = Timer(_reconnectDelay, () {});',
        '_t = Timer(Duration(seconds: _reconnectDelaySeconds), () {});',
        '_t = Timer.periodic(_liveTickInterval, (_) {});',
        'await Future.delayed(Duration.zero);'
      )
    ]
  });
  assert.deepEqual(result, { ok: true, problems: [] });
});

test('literal arithmetic in a duration fails, and so does arithmetic that mixes a literal with a variable', () => {
  const literal = checkTimers({ files: [dart('_t = Timer(Duration(seconds: 2 * 60), () {});')] });
  assert.equal(literal.ok, false);
  const mixed = checkTimers({ files: [dart('_t = Timer(Duration(milliseconds: graceMs + 1500), () {});')] });
  assert.equal(mixed.ok, false);
});

test('a TypeScript setTimeout or setInterval with a literal delay fails', () => {
  const result = checkTimers({
    files: [
      ts(
        'const a = setTimeout(() => done(), 200);',
        'const b = setInterval(tick, 60_000);',
        'await new Promise((resolve) => setTimeout(resolve, 1500));'
      )
    ]
  });
  assert.equal(result.ok, false);
  assert.deepEqual(rules(result), [1, 2, 3]);
});

test('a TypeScript timer with a named constant, variable or a delay expression without literals passes', () => {
  const result = checkTimers({
    files: [
      ts(
        'const a = setTimeout(() => done(), HEARTBEAT_MS);',
        'const b = setInterval(publish, heartbeatMs);',
        'await new Promise((resolve) => setTimeout(resolve, ms));',
        'const c = setTimeout(finish, graceMs);'
      )
    ]
  });
  assert.deepEqual(result, { ok: true, problems: [] });
});

test('literal arithmetic in a TypeScript delay fails', () => {
  const result = checkTimers({ files: [ts('const t = setTimeout(finish, graceMs + 1500);')] });
  assert.equal(result.ok, false);
});

test('identifiers that merely contain a digit are not literals', () => {
  const result = checkTimers({ files: [ts('const t = setTimeout(finish, retryV2Ms);')] });
  assert.deepEqual(result, { ok: true, problems: [] });
});

test('a timer name that merely ends in Timer is not a timer call', () => {
  const result = checkTimers({
    files: [dart('final x = _MinimizedElapsedTimer(startedAt: 5);', 'final y = myTimer(5);')]
  });
  assert.deepEqual(result, { ok: true, problems: [] });
});

test('test files are exempt, in every test folder and by name', () => {
  const result = checkTimers({
    files: [
      { path: 'apps/pi_frame/lib/a/widget_test.dart', contents: '_t = Timer(const Duration(seconds: 5), () {});' },
      { path: 'apps/agentd/src/a/thing.test.ts', contents: 'setTimeout(done, 200);' },
      { path: 'apps/agentd/src/journal/test/helper.ts', contents: 'setTimeout(done, 200);' }
    ]
  });
  assert.deepEqual(result, { ok: true, problems: [] });
});

test('commented-out timer calls are not counted', () => {
  const result = checkTimers({
    files: [dart('// _t = Timer(const Duration(seconds: 5), () {});', '/// Timer(Duration(seconds: 9))')]
  });
  assert.deepEqual(result, { ok: true, problems: [] });
});

test('reports every offending call with its file, line and a prescriptive message', () => {
  const result = checkTimers({
    files: [dart('_t = Timer(const Duration(seconds: 5), () {});'), ts('setTimeout(done, 200);')]
  });
  assert.equal(result.ok, false);
  assert.equal(result.problems.length, 2);
  for (const p of result.problems) {
    assert.equal(p.rule, 'timer-literal');
    assert.match(p.message, /const|constant/);
  }
});
