import test from 'node:test';
import assert from 'node:assert/strict';
import { checkDiagnostics, parseDartAnalyzeMachine } from '../src/index.mjs';

const diag = (rule, extra = {}) => ({
  tool: 'dart-analyze',
  package: 'apps/pi_frame',
  rule,
  severity: 'INFO',
  file: 'apps/pi_frame/lib/a.dart',
  line: 3,
  message: 'msg',
  ...extra
});
const baseline = (rule, count, pkg = 'apps/pi_frame') => ({ 'dart-analyze': { [pkg]: { [rule]: count } } });

test('parses dart analyze machine output (pipe-separated, escaped Windows paths, messages with pipes)', () => {
  const text = [
    'INFO|LINT|AVOID_PRINT|C:\\\\Repo\\\\lib\\\\probe.dart|5|12|5|Use a | logger, not print.',
    'WARNING|LINT|UNAWAITED_FUTURES|lib/a.dart|9|3|4|Future is not awaited.',
    'ERROR|STATIC_TYPE_WARNING|ARGUMENT_TYPE_NOT_ASSIGNABLE|lib/b.dart|1|1|1|bad type'
  ].join('\n');
  assert.deepEqual(parseDartAnalyzeMachine(text, { package: 'apps/pi_frame' }), [
    {
      tool: 'dart-analyze',
      package: 'apps/pi_frame',
      rule: 'avoid_print',
      severity: 'INFO',
      file: 'C:\\Repo\\lib\\probe.dart',
      line: 5,
      message: 'Use a | logger, not print.'
    },
    {
      tool: 'dart-analyze',
      package: 'apps/pi_frame',
      rule: 'unawaited_futures',
      severity: 'WARNING',
      file: 'lib/a.dart',
      line: 9,
      message: 'Future is not awaited.'
    },
    {
      tool: 'dart-analyze',
      package: 'apps/pi_frame',
      rule: 'argument_type_not_assignable',
      severity: 'ERROR',
      file: 'lib/b.dart',
      line: 1,
      message: 'bad type'
    }
  ]);
});

test('parser ignores blank lines and the human summary lines', () => {
  assert.deepEqual(parseDartAnalyzeMachine('\n  \n', { package: 'p' }), []);
});

test('equal counts pass', () => {
  const result = checkDiagnostics({ diagnostics: [diag('avoid_print')], baseline: baseline('avoid_print', 1) });
  assert.deepEqual(result, { ok: true, problems: [] });
});

test('an increase fails, names the new diagnostics and says how to fix the cause', () => {
  const result = checkDiagnostics({
    diagnostics: [diag('discarded_futures', { line: 7 }), diag('discarded_futures', { line: 9 })],
    baseline: baseline('discarded_futures', 1)
  });
  assert.equal(result.ok, false);
  assert.equal(result.problems.length, 1);
  const [problem] = result.problems;
  assert.deepEqual(
    {
      tool: problem.tool,
      package: problem.package,
      rule: problem.rule,
      baseline: problem.baseline,
      actual: problem.actual
    },
    { tool: 'dart-analyze', package: 'apps/pi_frame', rule: 'discarded_futures', baseline: 1, actual: 2 }
  );
  assert.match(problem.message, /dart-analyze apps\/pi_frame "discarded_futures": 1 → 2 \(\+1\)/);
  assert.match(problem.message, /apps\/pi_frame\/lib\/a\.dart:7/);
  assert.match(problem.message, /apps\/pi_frame\/lib\/a\.dart:9/);
  assert.match(problem.message, /wrap it in unawaited\(\.\.\.\)/);
  assert.match(problem.message, /do not raise the baseline/i);
});

test('locations in changed files are listed first, and a long list is capped at ten', () => {
  const many = Array.from({ length: 12 }, (_, i) =>
    diag('discarded_futures', { file: `apps/pi_frame/lib/f${i}.dart`, line: i + 1 })
  );
  const changed = diag('discarded_futures', { file: 'apps/pi_frame/lib/new.dart', line: 5 });
  const result = checkDiagnostics({
    diagnostics: [...many, changed],
    baseline: baseline('discarded_futures', 0),
    changedFiles: ['apps/pi_frame/lib/new.dart']
  });
  const message = result.problems[0].message;
  const lines = message.split('\n');
  assert.match(lines[1], /^ {4}apps\/pi_frame\/lib\/new\.dart:5/);
  assert.equal(message.match(/^ {4}apps\//gm).length, 10);
  assert.match(message, /and 3 more/);
});

test('a decrease fails with the exact baseline edit', () => {
  const result = checkDiagnostics({ diagnostics: [], baseline: baseline('avoid_print', 3) });
  assert.equal(result.ok, false);
  const [problem] = result.problems;
  assert.equal(problem.actual, 0);
  assert.match(problem.message, /3 → 0/);
  assert.match(problem.message, /tools\/guardrails\/diagnostics-baseline\.json/);
  assert.match(problem.message, /"dart-analyze" → "apps\/pi_frame"/);
  assert.match(problem.message, /change "avoid_print": 3 to "avoid_print": 0/);
});

test('a rule, package or tool absent from the baseline counts from zero', () => {
  const fails = checkDiagnostics({ diagnostics: [diag('avoid_print')], baseline: {} });
  assert.equal(fails.ok, false);
  assert.match(fails.problems[0].message, /0 → 1 \(\+1\)/);

  const passes = checkDiagnostics({ diagnostics: [], baseline: { 'dart-analyze': {} } });
  assert.deepEqual(passes, { ok: true, problems: [] });
});

test('tool is part of the key: the same rule under another tool is a separate count', () => {
  const result = checkDiagnostics({
    diagnostics: [diag('no_floating', { tool: 'eslint' })],
    baseline: baseline('no_floating', 0)
  });
  assert.equal(result.ok, false);
  assert.equal(result.problems[0].tool, 'eslint');
  assert.equal(result.problems[0].baseline, 0);
});
