/**
 * The escape-hatch ratchet. Counts the ways code silences a check (lint suppressions, type escapes, coverage
 * exclusions) per package, split into library and test code, and compares them with the committed baseline
 * (tools/guardrails/escape-hatch-baseline.json). Any difference fails: an increase with how to fix the root cause,
 * a decrease with the exact baseline edit, so the numbers can only go down.
 *
 * Pure: no I/O. tools/scripts/audit-escape-hatches.mjs reads the tracked files and the baseline and calls it.
 */

export const BASELINE_PATH = 'tools/guardrails/escape-hatch-baseline.json';

/** Package name → directory, in baseline order. Files outside these directories are not audited. */
const PACKAGES = [
  ['agentd', 'apps/agentd/'],
  ['pcp-ts', 'packages/pcp-ts/'],
  ['pcp-spec', 'packages/pcp-spec/'],
  ['pi_frame', 'apps/pi_frame/'],
  ['pi_frame_protocol', 'packages/pi_frame_protocol/'],
  ['pi_frame_theme', 'packages/pi_frame_theme/'],
  ['tools', 'tools/'],
  ['e2e', 'test/e2e/']
];

const KINDS = ['lib', 'test'];
const DART = /\.dart$/;
const SCRIPT = /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$/;

const TYPE_FIX =
  'Fix the type error instead of hiding it: give the value its real type, narrow it with a type guard, or correct ' +
  'the declaration that is wrong.';
const ANY_FIX =
  'Give the value its real type: import or declare the interface, use generics, or take `unknown` and narrow it ' +
  '(typeof / in / a schema validator) before use. In tests, build a complete typed fixture or a typed factory ' +
  'instead of casting partial data.';
const ANALYZER_FIX =
  'Fix the analyzer diagnostic the comment silences (for example replace the deprecated API, or use debugPrint / ' +
  'a logger instead of print) and delete the comment.';

/** In baseline order. `files` is the language the pattern applies to. */
const PATTERNS = [
  { name: '// ignore:', files: DART, regex: /\/\/\s*ignore:/g, fix: ANALYZER_FIX },
  { name: '// ignore_for_file:', files: DART, regex: /\/\/\s*ignore_for_file:/g, fix: ANALYZER_FIX },
  { name: '@ts-ignore', files: SCRIPT, regex: /@ts-ignore\b/g, fix: TYPE_FIX },
  { name: '@ts-expect-error', files: SCRIPT, regex: /@ts-expect-error\b/g, fix: TYPE_FIX },
  { name: '@ts-nocheck', files: SCRIPT, regex: /@ts-nocheck\b/g, fix: TYPE_FIX },
  {
    name: 'eslint-disable',
    files: SCRIPT,
    regex: /eslint-disable/g,
    fix: 'ESLint is not installed in this repository, so the comment disables nothing: delete it, and fix the code the rule would flag.'
  },
  { name: 'as any', files: SCRIPT, regex: /\bas\s+any\b/g, fix: ANY_FIX },
  { name: ': any', files: SCRIPT, regex: /:\s*any\b/g, fix: ANY_FIX },
  { name: 'as unknown as', files: SCRIPT, regex: /\bas\s+unknown\s+as\b/g, fix: ANY_FIX },
  {
    name: '// coverage:ignore',
    files: /\.(dart|ts|tsx|mts|cts|js|jsx|mjs|cjs)$/,
    regex: /coverage:ignore/g,
    fix: 'Write a test that covers the code instead of excluding it from coverage; delete code no test can reach.'
  }
];

/** Build output, dependencies and caches: never audited. */
const EXCLUDED_DIRS = new Set(['node_modules', 'dist', 'build', 'out', 'coverage', '.dart_tool', '.pub-cache']);
const TEST_DIRS = new Set(['test', 'tests', '__tests__']);
const TEST_NAME = /(_test\.dart|\.(test|spec)\.(ts|tsx|mts|cts|js|jsx|mjs|cjs))$/;
/** This module and its tests spell out every pattern, so they are not counted. */
const SELF = new Set(['tools/guardrails/src/escape-hatches.mjs', 'tools/guardrails/test/escape-hatches.test.mjs']);

/**
 * @typedef {Record<string, Record<'lib' | 'test', Record<string, number>>>} EscapeHatchCounts package → kind → pattern → count
 * @typedef {object} Mismatch
 * @property {string} package
 * @property {'lib' | 'test' | undefined} kind
 * @property {string | undefined} pattern
 * @property {number | undefined} baseline
 * @property {number | undefined} actual
 * @property {string} message what is wrong and how to fix it
 */

/**
 * @param {object} input
 * @param {{ path: string, contents: string }[]} input.files tracked files, repository-relative paths with `/`
 * @param {EscapeHatchCounts} input.baseline the committed baseline
 * @param {string[]} [input.changedPaths] files changed on this branch; listed first when a count goes up
 * @returns {{ ok: boolean, counts: EscapeHatchCounts, mismatches: Mismatch[] }}
 */
export function auditEscapeHatches({ files, baseline, changedPaths = [] }) {
  /** @type {EscapeHatchCounts} */
  const counts = {};
  /** package → kind → pattern → file → line numbers */
  const hits = {};
  for (const [pkg] of PACKAGES) {
    counts[pkg] = {};
    hits[pkg] = {};
    for (const kind of KINDS) {
      counts[pkg][kind] = Object.fromEntries(PATTERNS.map((p) => [p.name, 0]));
      hits[pkg][kind] = Object.fromEntries(PATTERNS.map((p) => [p.name, new Map()]));
    }
  }

  for (const { path: rawPath, contents } of files) {
    const path = rawPath.replaceAll('\\', '/');
    const entry = PACKAGES.find(([, dir]) => path.startsWith(dir));
    if (!entry || SELF.has(path)) continue;
    const [pkg, dir] = entry;
    const segments = path.slice(dir.length).split('/');
    const name = segments.pop();
    if (segments.some((s) => EXCLUDED_DIRS.has(s))) continue;
    const kind = segments.some((s) => TEST_DIRS.has(s)) || TEST_NAME.test(name) ? 'test' : 'lib';
    const patterns = PATTERNS.filter((p) => p.files.test(name));
    if (patterns.length === 0) continue;
    const lines = contents.split(/\r?\n/);
    for (const pattern of patterns) {
      lines.forEach((line, i) => {
        const n = line.match(pattern.regex)?.length ?? 0;
        if (n === 0) return;
        counts[pkg][kind][pattern.name] += n;
        const byFile = hits[pkg][kind][pattern.name];
        if (!byFile.has(path)) byFile.set(path, []);
        byFile.get(path).push(i + 1);
      });
    }
  }

  const changed = new Set(changedPaths.map((p) => p.replaceAll('\\', '/')));
  /** @type {Mismatch[]} */
  const mismatches = [];
  for (const [pkg] of PACKAGES) {
    for (const kind of KINDS) {
      for (const pattern of PATTERNS) {
        const actual = counts[pkg][kind][pattern.name];
        const expected = baseline?.[pkg]?.[kind]?.[pattern.name];
        const where = `${pkg} ${kind} "${pattern.name}"`;
        const at = { package: pkg, kind, pattern: pattern.name, baseline: expected, actual };
        if (typeof expected !== 'number') {
          mismatches.push({
            ...at,
            baseline: undefined,
            message:
              `${where}: no entry in the baseline. Add "${pattern.name}": ${actual} under "${pkg}" → "${kind}" in ` +
              `${BASELINE_PATH} (every package, kind and pattern is listed, zeros included).`
          });
        } else if (actual > expected) {
          mismatches.push({
            ...at,
            message: increaseMessage(where, expected, actual, pattern, hits[pkg][kind], changed)
          });
        } else if (actual < expected) {
          mismatches.push({
            ...at,
            message:
              `${where}: ${expected} → ${actual} (${actual - expected}). Escape hatches were removed, well done: ` +
              `lower the baseline in the same commit.\n  Edit ${BASELINE_PATH}, "${pkg}" → "${kind}": change ` +
              `"${pattern.name}": ${expected} to "${pattern.name}": ${actual}`
          });
        }
      }
    }
  }
  mismatches.push(...unknownEntries(baseline));
  return { ok: mismatches.length === 0, counts, mismatches };
}

function increaseMessage(where, expected, actual, pattern, kindHits, changed) {
  const files = [...kindHits[pattern.name].entries()].sort(
    ([a], [b]) => Number(changed.has(b)) - Number(changed.has(a)) || a.localeCompare(b)
  );
  const list = files.map(([file, lines]) => `    ${file}:${lines.join(', ')}${changed.has(file) ? ' (changed)' : ''}`);
  return (
    `${where}: ${expected} → ${actual} (+${actual - expected}). A new escape hatch silences a check.\n` +
    `  Occurrences (files changed since the baseline was last updated first):\n${list.join('\n')}\n` +
    `  Fix the root cause: ${pattern.fix}\n` +
    `  Do not raise the baseline to make this pass: an increase needs a human's decision (the \`human-approved\` ` +
    `label on the pull request).`
  );
}

function unknownEntries(baseline) {
  const known = new Map(PACKAGES);
  const patternNames = new Set(PATTERNS.map((p) => p.name));
  const out = [];
  for (const [pkg, kinds] of Object.entries(baseline ?? {})) {
    if (!known.has(pkg)) {
      out.push({
        package: pkg,
        message: `${BASELINE_PATH}: package "${pkg}" is unknown to the audit. Remove it, or add its directory to the audit's package list.`
      });
      continue;
    }
    for (const [kind, patterns] of Object.entries(kinds ?? {})) {
      if (!KINDS.includes(kind)) {
        out.push({
          package: pkg,
          message: `${BASELINE_PATH}: "${pkg}" → "${kind}" is unknown (use lib or test). Remove it.`
        });
        continue;
      }
      for (const name of Object.keys(patterns ?? {})) {
        if (!patternNames.has(name)) {
          out.push({
            package: pkg,
            kind,
            pattern: name,
            message: `${BASELINE_PATH}: pattern "${name}" under "${pkg}" → "${kind}" is unknown to the audit. Remove it.`
          });
        }
      }
    }
  }
  return out;
}
