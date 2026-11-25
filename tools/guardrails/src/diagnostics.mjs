/**
 * The diagnostics ratchet. Counts the diagnostics each analyzer reports per tool × package × rule and compares them
 * with the committed baseline (tools/guardrails/diagnostics-baseline.json). A missing entry counts from zero, so a
 * new rule or package with a diagnostic fails. An increase fails with the new diagnostics and how to fix the cause; a
 * decrease fails with the exact baseline edit, so the baseline only shrinks. Ticket by ticket the counts go to zero;
 * the mechanism stays for future exceptions, which need a human's approval (the guarded baseline file).
 *
 * Pure: no I/O. tools/scripts/lint-flutter.mjs runs the analyzers, parses their output with the functions here, and calls
 * checkDiagnostics. A tool's parser lives here too, so its output format is tested on captured fixture text.
 */
import { APPROVAL_LABEL } from './label.mjs';

export const DIAGNOSTICS_BASELINE_PATH = 'tools/guardrails/diagnostics-baseline.json';

/** How to fix the cause, per rule. Unknown rules get the generic advice. */
const FIXES = {
  discarded_futures:
    'await the future, or, when nothing depends on its result, wrap it in unawaited(...) so the choice is explicit',
  unawaited_futures: 'await the future, or wrap it in unawaited(...) when nothing depends on its result',
  avoid_dynamic_calls: 'declare the type of the value and call the member on that type instead of on dynamic',
  strict_raw_type: 'give the generic type its type arguments',
  inference_failure_on_collection_literal: 'declare the element type of the collection literal',
  avoid_print: 'use the app logging path (debugPrint or the logger) instead of print'
};
/** How many locations an increase message lists. */
const LOCATIONS_SHOWN = 10;
const GENERIC_FIX = 'fix the diagnostic the analyzer reports at the locations listed, rather than silencing it';

/**
 * Parses `dart analyze --format=machine` output: one `SEVERITY|TYPE|CODE|FILE|LINE|COLUMN|LENGTH|MESSAGE` record per
 * line (the message may contain `|`; backslashes in the file path are escaped). Other lines are ignored.
 *
 * @param {string} text the analyzer's standard output
 * @param {{ package: string, tool?: string }} options the package the analysis ran in; the tool name (default
 *   `dart-analyze`) is part of the ratchet key
 * @returns {{ tool: string, package: string, rule: string, severity: string, file: string, line: number, message: string }[]}
 */
export function parseDartAnalyzeMachine(text, { package: pkg, tool = 'dart-analyze' }) {
  const out = [];
  for (const line of text.split(/\r?\n/)) {
    const fields = line.split('|');
    if (fields.length < 8 || !/^(INFO|WARNING|ERROR|HINT)$/.test(fields[0])) continue;
    const [severity, , rule, file, lineNo, , , ...rest] = fields;
    out.push({
      tool,
      package: pkg,
      rule: rule.toLowerCase(),
      severity,
      file: file.replace(/\\\\/g, '\\'),
      line: Number(lineNo),
      message: rest.join('|')
    });
  }
  return out;
}

/** `tsc` diagnostic lines: `path(line,col): error TSnnnn: message`. Continuation lines are indented and ignored. */
const TSC_LINE = /^(.+?)\((\d+),\d+\): (error|warning) (TS\d+): (.*)$/;

/**
 * Parses `tsc --noEmit --pretty false` output. The rule is the diagnostic code (`TS2532`); the file is as tsc printed
 * it (relative to the package folder the check ran in).
 *
 * @param {string} text the compiler's standard output
 * @param {{ package: string, tool?: string }} options the package the check ran in; the tool name (default `tsc`) is
 *   part of the ratchet key
 * @returns {{ tool: string, package: string, rule: string, severity: string, file: string, line: number, message: string }[]}
 */
export function parseTscOutput(text, { package: pkg, tool = 'tsc' }) {
  const out = [];
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(TSC_LINE);
    if (!match) continue;
    const [, file, lineNo, severity, code, message] = match;
    out.push({
      tool,
      package: pkg,
      rule: code,
      severity: severity.toUpperCase(),
      file: file.replace(/\\/g, '/'),
      line: Number(lineNo),
      message
    });
  }
  return out;
}

/**
 * Parses ESLint's `--format json` report. Each message becomes one diagnostic: the rule is `ruleId` (`parse-error`
 * for a fatal message without one). Messages of severity 1 are WARNING, 2 are ERROR. The package is the longest of
 * `packages` that contains the file, so one ESLint run over every package still counts per package.
 *
 * @param {string} text the JSON report
 * @param {{ repoRoot: string, packages: string[], tool?: string }} options the repository root the file paths are
 *   absolute to, the package folders (repository-relative), and the tool name (default `eslint`)
 * @returns {{ tool: string, package: string, rule: string, severity: string, file: string, line: number, message: string }[]}
 */
export function parseEslintJson(text, { repoRoot, packages, tool = 'eslint' }) {
  const norm = (p) => p.replace(/\\/g, '/').replace(/\/+$/, '');
  const root = norm(repoRoot);
  const owners = [...packages].sort((a, b) => b.length - a.length);
  const out = [];
  for (const report of JSON.parse(text)) {
    const file = norm(report.filePath).slice(root.length + 1);
    const pkg = owners.find((dir) => file === dir || file.startsWith(`${dir}/`)) ?? 'repository';
    for (const message of report.messages) {
      out.push({
        tool,
        package: pkg,
        rule: message.ruleId ?? 'parse-error',
        severity: message.severity === 2 ? 'ERROR' : 'WARNING',
        file,
        line: message.line,
        message: message.message
      });
    }
  }
  return out;
}

/** Counts diagnostics as tool → package → rule → count. */
function countByKey(diagnostics) {
  const counts = {};
  for (const d of diagnostics) {
    const rules = ((counts[d.tool] ??= {})[d.package] ??= {});
    rules[d.rule] = (rules[d.rule] ?? 0) + 1;
  }
  return counts;
}

/**
 * @param {object} input
 * @param {{ tool: string, package: string, rule: string, file: string, line: number, message: string }[]} input.diagnostics
 *   every diagnostic the tools report now
 * @param {Record<string, Record<string, Record<string, number>>>} input.baseline the committed counts
 * @param {string[]} [input.changedFiles] repository-relative files this branch changes, listed first in a message
 * @returns {{ ok: boolean, problems: { tool: string, package: string, rule: string, baseline: number, actual: number,
 *   message: string }[] }}
 */
export function checkDiagnostics({ diagnostics, baseline, changedFiles = [] }) {
  const changed = new Set(changedFiles);
  const counts = countByKey(diagnostics);
  const problems = [];
  const keys = new Set();
  for (const source of [counts, baseline ?? {}]) {
    for (const [tool, packages] of Object.entries(source)) {
      for (const [pkg, rules] of Object.entries(packages ?? {})) {
        for (const rule of Object.keys(rules ?? {})) keys.add(JSON.stringify([tool, pkg, rule]));
      }
    }
  }
  for (const key of [...keys].sort()) {
    const [tool, pkg, rule] = JSON.parse(key);
    const expected = baseline?.[tool]?.[pkg]?.[rule] ?? 0;
    const actual = counts[tool]?.[pkg]?.[rule] ?? 0;
    if (actual === expected) continue;
    const where = `${tool} ${pkg} "${rule}"`;
    if (actual > expected) {
      // Locations in files this branch changed come first: a new diagnostic is almost always in one of them.
      const found = diagnostics
        .filter((d) => d.tool === tool && d.package === pkg && d.rule === rule)
        .sort((a, b) => Number(changed.has(b.file)) - Number(changed.has(a.file)));
      const shown = found.slice(0, LOCATIONS_SHOWN).map((d) => `    ${d.file}:${d.line} ${d.message}`);
      if (found.length > LOCATIONS_SHOWN) shown.push(`    ... and ${found.length - LOCATIONS_SHOWN} more`);
      problems.push({
        tool,
        package: pkg,
        rule,
        baseline: expected,
        actual,
        message:
          `${where}: ${expected} → ${actual} (+${actual - expected}). Diagnostics of this rule in ${pkg} ` +
          `(files changed on this branch first):\n` +
          `${shown.join('\n')}\n` +
          `  Fix the root cause: ${FIXES[rule] ?? GENERIC_FIX}.\n` +
          `  Do not raise the baseline to make this pass: an increase needs a human's decision (the \`${APPROVAL_LABEL}\` ` +
          'label on the pull request).'
      });
    } else {
      problems.push({
        tool,
        package: pkg,
        rule,
        baseline: expected,
        actual,
        message:
          `${where}: ${expected} → ${actual} (${actual - expected}). Diagnostics were fixed, well done: lower the ` +
          `baseline in the same commit.\n` +
          `  Edit ${DIAGNOSTICS_BASELINE_PATH}, "${tool}" → "${pkg}": change "${rule}": ${expected} to "${rule}": ${actual}`
      });
    }
  }
  return { ok: problems.length === 0, problems };
}
