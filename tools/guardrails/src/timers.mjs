/**
 * Named timers: every timer in the app and the daemon has a named reason. A timer call whose duration is a numeric
 * literal, or arithmetic that contains one, fails; a named constant or a variable passes. Covers Dart `Timer(`,
 * `Timer.periodic(` and `Future.delayed(` (duration is the first argument) and TypeScript `setTimeout(` and
 * `setInterval(` (delay is the second argument). Test code, comments and identifiers that merely contain a digit are
 * not counted.
 *
 * Pure: no I/O. tools/scripts/check-timers.mjs reads the tracked files and calls it. See docs/pr-verification.md.
 */
import { DART_FILE, SCRIPT_FILE, TEST_FILE_NAME, toPosix } from './paths.mjs';

const TEST_DIRS = new Set(['test', 'tests', '__tests__']);
/** A digit that starts a number, not a digit inside an identifier such as `retryV2Ms`. */
const NUMBER_LITERAL = /(?<![\w$])\d/;

/** The timer calls, the argument that carries the duration, and the languages each one appears in. */
const CALLS = [
  { call: 'Timer(', regex: /\bTimer\(/g, argument: 0, files: DART_FILE, kind: 'Dart' },
  { call: 'Timer.periodic(', regex: /\bTimer\.periodic\(/g, argument: 0, files: DART_FILE, kind: 'Dart' },
  { call: 'Future.delayed(', regex: /\bFuture\.delayed\(/g, argument: 0, files: DART_FILE, kind: 'Dart' },
  { call: 'setTimeout(', regex: /\bsetTimeout\(/g, argument: 1, files: SCRIPT_FILE, kind: 'TypeScript' },
  { call: 'setInterval(', regex: /\bsetInterval\(/g, argument: 1, files: SCRIPT_FILE, kind: 'TypeScript' }
];

/** Whether a path is test code: a `*_test.dart` / `*.test.ts` name, or a file in a test folder. */
const isTestCode = (path) => TEST_FILE_NAME.test(path) || path.split('/').some((s) => TEST_DIRS.has(s));

/**
 * The top-level arguments of a call whose opening parenthesis is at `open`. Quoted text is skipped so a comma or
 * parenthesis inside a string does not split or close the call. Returns undefined when the call never closes.
 */
function callArguments(text, open) {
  const args = [];
  let depth = 0;
  let quote;
  let start = open + 1;
  for (let i = open + 1; i < text.length; i++) {
    const c = text[i];
    if (quote) {
      if (c === '\\') i++;
      else if (c === quote) quote = undefined;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') quote = c;
    else if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') {
      if (depth === 0) {
        args.push(text.slice(start, i));
        return args.map((a) => a.trim());
      }
      depth--;
    } else if (c === ',' && depth === 0) {
      args.push(text.slice(start, i));
      start = i + 1;
    }
  }
  return undefined;
}

/** Whether the match sits in a comment: its line starts with `//`, `/*` or a doc-comment `*`. */
function inComment(text, index) {
  const lineStart = text.lastIndexOf('\n', index - 1) + 1;
  const lineEnd = text.indexOf('\n', index);
  const line = text.slice(lineStart, lineEnd === -1 ? text.length : lineEnd).trim();
  return line.startsWith('//') || line.startsWith('/*') || line.startsWith('*');
}

const lineOf = (text, index) => text.slice(0, index).split('\n').length;

function fixMessage(call, kind, argument) {
  const example = kind === 'Dart' ? 'const _tickInterval = Duration(seconds: 1);' : 'const TICK_MS = 1000;';
  return (
    `${call} takes a literal duration (\`${argument}\`). Name the delay: declare a named constant next to its use, ` +
    `for example \`${example}\`, named for why the wait exists, and pass that name instead.`
  );
}

/**
 * @param {object} input
 * @param {{ path: string, contents: string }[]} input.files source files, repository-relative paths with `/`
 * @returns {{ ok: boolean, problems: { rule: 'timer-literal', path: string, line: number, message: string }[] }}
 */
export function checkTimers({ files }) {
  const problems = [];
  for (const { path: rawPath, contents } of files) {
    const path = toPosix(rawPath);
    if (isTestCode(path)) continue;
    for (const spec of CALLS) {
      if (!spec.files.test(path)) continue;
      for (const match of contents.matchAll(spec.regex)) {
        if (inComment(contents, match.index)) continue;
        const open = match.index + match[0].length - 1;
        const args = callArguments(contents, open);
        const duration = args?.[spec.argument];
        if (duration === undefined || !NUMBER_LITERAL.test(duration)) continue;
        problems.push({
          rule: 'timer-literal',
          path,
          line: lineOf(contents, match.index),
          message: fixMessage(spec.call, spec.kind, duration)
        });
      }
    }
  }
  problems.sort((a, b) => (a.path === b.path ? a.line - b.line : a.path < b.path ? -1 : 1));
  return { ok: problems.length === 0, problems };
}
