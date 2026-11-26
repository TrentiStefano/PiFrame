/**
 * Affected Flutter tests: the `*_test.dart` files whose imports reach a changed Dart file, directly or through other
 * files. `check` runs them, so the inner loop sees what a change breaks in tests that only reach it indirectly (an app
 * shell test that imports a provider through the shell, #116). Follows `import`, `export` and `part` directives:
 * `package:<name>/<path>` resolves to `<project>/lib/<path>` for the repository's own Flutter projects, relative URIs
 * to the importing file's folder; `dart:` and third-party packages are ignored.
 *
 * Pure: no I/O. tools/scripts/check.mjs reads the files and the changed paths and calls it. See
 * docs/pr-verification.md ("Affected Flutter tests").
 */
import { posix } from 'node:path';

const DIRECTIVE = /^\s*(?:import|export|part)\s+['"]([^'"]+)['"]/gm;
const TEST_FILE = /_test\.dart$/;

/**
 * @param {object} input
 * @param {{ path: string, contents: string }[]} input.files every Dart file of the Flutter projects, `/`-separated
 * @param {{ dir: string, package: string }[]} input.projects each Flutter project's folder and pubspec name
 * @param {string[]} input.changed paths changed on the branch or in the working tree, `/`-separated
 * @returns {Record<string, string[]>} per project folder, the affected test files relative to it, sorted
 */
export function affectedDartTests({ files, projects, changed }) {
  const known = new Set(files.map((f) => f.path));
  const importers = new Map();
  for (const { path, contents } of files) {
    for (const match of contents.matchAll(DIRECTIVE)) {
      const target = resolve(path, match[1], projects);
      if (!target || !known.has(target)) continue;
      if (!importers.has(target)) importers.set(target, new Set());
      importers.get(target).add(path);
    }
  }

  const reached = new Set();
  const queue = changed.filter((p) => known.has(p));
  while (queue.length > 0) {
    const path = queue.pop();
    if (reached.has(path)) continue;
    reached.add(path);
    for (const importer of importers.get(path) ?? []) queue.push(importer);
  }

  /** @type {Record<string, string[]>} */
  const result = {};
  for (const { dir } of projects) {
    const tests = [...reached]
      .filter((p) => p.startsWith(`${dir}/test/`) && TEST_FILE.test(p))
      .map((p) => p.slice(dir.length + 1))
      .sort();
    if (tests.length > 0) result[dir] = tests;
  }
  return result;
}

/** The repository path a directive's URI names, or undefined for `dart:` and third-party packages. */
function resolve(from, uri, projects) {
  const pkg = uri.match(/^package:([^/]+)\/(.+)$/);
  if (pkg) {
    const project = projects.find((p) => p.package === pkg[1]);
    return project ? `${project.dir}/lib/${pkg[2]}` : undefined;
  }
  if (/^[a-z]+:/.test(uri)) return undefined;
  return posix.normalize(posix.join(posix.dirname(from), uri));
}
