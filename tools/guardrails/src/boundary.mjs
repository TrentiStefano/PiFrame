/**
 * Import boundaries: the layer rules of the Flutter app (apps/pi_frame/lib), the daemon's allowed-dependency table and
 * module-cycle rule (apps/agentd/src), and the rule that packages never depend on apps. Violations that exist today
 * are listed in the committed baseline (BOUNDARY_CONFIG_PATH); a violation not in it fails, and so does a baseline
 * entry that no longer matches anything. See docs/pr-verification.md ("Import boundaries").
 *
 * Pure: no I/O. tools/scripts/check-boundaries.mjs reads the tracked files and the config and calls it.
 */
import { posix } from 'node:path';
import { DART_FILE, TEST_FILE_NAME, toPosix } from './paths.mjs';

/** The committed table and baseline the check reads, relative to the repository root. */
export const BOUNDARY_CONFIG_PATH = 'tools/guardrails/boundary.json';

const APP_LIB = 'apps/pi_frame/lib/';
const DAEMON_SRC = 'apps/agentd/src/';
const APPS = 'apps/';
const PACKAGES = 'packages/';

/** Raw I/O and platform plugins, by SDK library (`dart:io`) or by package name (`http` for `package:http/...`). */
const RAW_IO = new Set([
  'dart:io',
  'dart:ffi',
  'ffi',
  'http',
  'web_socket_channel',
  'win32',
  'url_launcher',
  'file_selector',
  'desktop_drop',
  'window_manager',
  'local_notifier',
  'webview_win_floating'
]);

/** The app layers a file in each layer must not import. Features may import each other, and any app layer. */
const FORBIDDEN_LAYERS = {
  domain: ['data', 'features', 'ui', 'app'],
  data: ['features', 'ui', 'app'],
  ui: ['features', 'app', 'data'],
  features: ['app']
};
/** Framework packages domain/ must not import: domain holds plain models, not Flutter widgets or Riverpod state. */
const DOMAIN_FRAMEWORK_RULES = [
  { prefix: 'package:flutter/', rule: 'domain-flutter' },
  { prefix: 'package:flutter_riverpod/', rule: 'domain-riverpod' },
  { prefix: 'package:riverpod/', rule: 'domain-riverpod' }
];
/**
 * Folders a layer may import although their layer is forbidden to it. Shared widgets show user-facing text, and all
 * user-facing text comes from the translation tables in data/language/ (presentation, not I/O).
 */
const ALLOWED_INTO_FORBIDDEN = {
  ui: [`${APP_LIB}data/language/`]
};
/** Layers that may import the test harness: the app shell and the entry points. */
const HARNESS_IMPORTERS = ['app', 'entry', 'harness'];
/** Layers that must not touch raw I/O or platform plugins directly. */
const NO_RAW_IO = ['domain', 'features', 'ui'];

const DART_DIRECTIVE = /^[ \t]*(?:import|export)\s+([^;]*);/gm;
const DART_QUOTED = /'([^']*)'|"([^"]*)"/g;
const TS_IMPORT =
  /\b(?:import|export)\b[^'"`;]*?\bfrom\s*['"]([^'"]+)['"]|\bimport\s*['"]([^'"]+)['"]|\bimport\(\s*['"]([^'"]+)['"]\s*\)/g;

const lineAt = (contents, index) => contents.slice(0, index).split('\n').length;

/** Every import and export URI in a Dart file, with its line. Conditional imports list every URI they name. */
function dartImports(contents) {
  return [...contents.matchAll(DART_DIRECTIVE)].flatMap((m) => {
    const line = lineAt(contents, m.index);
    return [...m[1].matchAll(DART_QUOTED)].map((q) => ({ spec: q[1] ?? q[2], line }));
  });
}

/** Every import, export-from and literal dynamic import() specifier in a TypeScript file, with its line. */
function tsImports(contents) {
  return [...contents.matchAll(TS_IMPORT)].map((m) => ({
    spec: m[1] ?? m[2] ?? m[3],
    line: lineAt(contents, m.index)
  }));
}

const isTestFile = (path) => TEST_FILE_NAME.test(path) || path.split('/').includes('test');

/** The app layer of a lib-relative file: its first folder, or `entry` for a file at the root of lib. */
function appLayer(path) {
  const rel = path.slice(APP_LIB.length);
  const slash = rel.indexOf('/');
  return slash === -1 ? 'entry' : rel.slice(0, slash);
}

/** The Dart file a `package:pi_frame/` or relative import names (repository path), or null for other packages. */
function resolveDart(from, spec) {
  if (spec.startsWith('package:pi_frame/')) return APP_LIB + spec.slice('package:pi_frame/'.length);
  if (spec.includes(':')) return null;
  return posix.join(posix.dirname(from), spec);
}

/** The repository path a relative TypeScript import names, or null for packages. */
const resolveTs = (from, spec) => (spec.startsWith('.') ? posix.join(posix.dirname(from), spec) : null);

/** The daemon module a file belongs to: its first folder under src/, or the file name for a file at the root. */
function daemonModule(path) {
  const rel = path.slice(DAEMON_SRC.length);
  const slash = rel.indexOf('/');
  return slash === -1 ? rel.replace(/\.ts$/, '') : rel.slice(0, slash);
}

/** The RAW_IO key of an import: the SDK library, or the package name. */
const rawKey = (spec) => (spec.startsWith('package:') ? spec.slice('package:'.length).split('/')[0] : spec);

function dartViolations(path, contents) {
  const from = appLayer(path);
  const out = [];
  for (const { spec, line } of dartImports(contents)) {
    const target = resolveDart(path, spec);
    const to = target?.startsWith(APP_LIB) ? appLayer(target) : undefined;
    const at = { file: path, import: spec, line };
    const framework = from === 'domain' ? DOMAIN_FRAMEWORK_RULES.find((r) => spec.startsWith(r.prefix)) : undefined;
    if (framework) {
      out.push({ ...at, rule: framework.rule, message: rawMessage(at, 'domain') });
    } else if (NO_RAW_IO.includes(from) && RAW_IO.has(rawKey(spec))) {
      out.push({ ...at, rule: 'raw-io', message: rawMessage(at, from) });
    }
    if (to === 'harness' && !HARNESS_IMPORTERS.includes(from)) {
      out.push({ ...at, rule: 'harness', message: harnessMessage(at, from) });
    } else if (
      to &&
      (FORBIDDEN_LAYERS[from] ?? []).includes(to) &&
      !(ALLOWED_INTO_FORBIDDEN[from] ?? []).some((prefix) => target.startsWith(prefix))
    ) {
      out.push({ ...at, rule: 'layer', message: layerMessage(at, from, to) });
    }
  }
  return out;
}

function rawMessage({ file, import: spec, line }, from) {
  if (from === 'domain' && DOMAIN_FRAMEWORK_RULES.some((r) => spec.startsWith(r.prefix))) {
    return `${file}:${line} imports '${spec}': domain/ must stay pure Dart. Move the Flutter- or Riverpod-dependent code into data/, features/ or ui/ and keep only the plain model here.`;
  }
  return (
    `${file}:${line} imports '${spec}' in ${from}/, which must not use raw I/O or platform plugins. ` +
    'Move that call into a service in data/, read it in this file through a provider, and test the feature with a fake ' +
    'of the service (docs/pr-verification.md, "Import boundaries").'
  );
}

function harnessMessage({ file, import: spec, line }, from) {
  return (
    `${file}:${line} imports '${spec}' from ${from}/, but harness/ may be imported only by app/ and the entry points ` +
    '(lib/main*.dart). Remove the import and reach the harness through app/.'
  );
}

function layerMessage({ file, import: spec, line }, from, to) {
  return (
    `${file}:${line} imports '${spec}' from ${to}/, but ${from}/ must not depend on ${to}/. Invert the dependency: ` +
    'pass the value in, or move the shared plain type down into domain/ (docs/pr-verification.md, "Import boundaries").'
  );
}

function daemonViolations(path, contents, own, table, graph) {
  const out = [];
  for (const { spec, line } of tsImports(contents)) {
    const target = resolveTs(path, spec);
    if (!target?.startsWith(DAEMON_SRC)) continue;
    const to = daemonModule(target);
    if (to === own) continue;
    if (!graph.has(own)) graph.set(own, new Set());
    graph.get(own).add(to);
    if (!(table[own] ?? []).includes(to)) {
      out.push({
        file: path,
        import: spec,
        line,
        rule: 'daemon-edge',
        message:
          `${path}:${line} imports '${spec}': module '${own}' may not depend on module '${to}'. Remove the import, or ` +
          `add the edge to the allowed-dependency table in ${BOUNDARY_CONFIG_PATH} after review (record it in docs/adr/).`
      });
    }
  }
  return out;
}

const reachable = (graph, start) => {
  const seen = new Set();
  const queue = [...(graph.get(start) ?? [])];
  while (queue.length) {
    const node = queue.shift();
    if (seen.has(node)) continue;
    seen.add(node);
    queue.push(...(graph.get(node) ?? []));
  }
  return seen;
};

/** One shortest loop through `start` inside its strongly connected component, as `a -> b -> ... -> a`. */
function findLoop(graph, start, component) {
  const parent = new Map();
  const queue = [start];
  while (queue.length) {
    const node = queue.shift();
    for (const next of graph.get(node) ?? []) {
      if (!component.has(next)) continue;
      if (next === start) {
        const loop = [node];
        for (let x = node; x !== start; x = parent.get(x)) loop.unshift(parent.get(x));
        return [...loop, start].join(' -> ');
      }
      if (!parent.has(next)) {
        parent.set(next, node);
        queue.push(next);
      }
    }
  }
  return undefined;
}

/** One problem per module cycle: the strongly connected components of the daemon module graph with more than one module. */
function cycleViolations(graph) {
  const nodes = [...graph.keys()].sort();
  const reach = new Map(nodes.map((n) => [n, reachable(graph, n)]));
  const done = new Set();
  const out = [];
  for (const start of nodes) {
    if (done.has(start)) continue;
    const component = new Set([start, ...nodes.filter((n) => reach.get(start).has(n) && reach.get(n).has(start))]);
    for (const n of component) done.add(n);
    if (component.size === 1) continue;
    const loop = findLoop(graph, start, component);
    out.push({
      file: `${DAEMON_SRC}${start}`,
      import: loop,
      rule: 'cycle',
      message:
        `apps/agentd/src modules form a cycle: ${loop}. Break it: move the shared code into a module of its own, or ` +
        'invert one of the imports. Then remove the baseline entry.'
    });
  }
  return out;
}

function packageViolations(path, contents) {
  const specs = path.endsWith('.dart')
    ? dartImports(contents).map((i) => ({ ...i, target: resolveDart(path, i.spec) }))
    : tsImports(contents).map((i) => ({ ...i, target: resolveTs(path, i.spec) }));
  return specs
    .filter(({ target }) => target?.startsWith(APPS))
    .map(({ spec, line }) => ({
      file: path,
      import: spec,
      line,
      rule: 'packages-to-apps',
      message: `${path}:${line} imports '${spec}' from apps/: packages/ must never depend on apps/. Move the shared code into a package.`
    }));
}

/**
 * @param {object} input
 * @param {{ path: string, contents: string }[]} input.files tracked source files, `/`-separated repository paths
 * @param {Record<string, string[]>} input.daemonAllowedDependencies the daemon module table: module → modules it may import
 * @param {{ file: string, import: string }[]} input.baseline violations that exist today and are accepted for now
 * @returns {{ ok: boolean, problems: { file: string, import: string, rule: string, message: string, line?: number }[] }}
 */
export function checkBoundaries({ files, daemonAllowedDependencies = {}, baseline = [] }) {
  const violations = [];
  const graph = new Map();
  for (const { path: raw, contents } of files) {
    const path = toPosix(raw);
    if (isTestFile(path)) continue;
    const isTs = path.endsWith('.ts') && !path.endsWith('.d.ts');
    if (path.startsWith(APP_LIB) && DART_FILE.test(path)) {
      violations.push(...dartViolations(path, contents));
    } else if (path.startsWith(DAEMON_SRC) && isTs) {
      violations.push(...daemonViolations(path, contents, daemonModule(path), daemonAllowedDependencies, graph));
    } else if (path.startsWith(PACKAGES) && (isTs || DART_FILE.test(path))) {
      violations.push(...packageViolations(path, contents));
    }
  }
  violations.push(...cycleViolations(graph));

  const key = (file, spec) => `${file}\n${spec}`;
  const accepted = new Set(baseline.map((entry) => key(entry.file, entry.import)));
  const found = new Set(violations.map((v) => key(v.file, v.import)));
  const problems = violations.filter((v) => !accepted.has(key(v.file, v.import)));
  for (const entry of baseline) {
    if (found.has(key(entry.file, entry.import))) continue;
    problems.push({
      file: entry.file,
      import: entry.import,
      rule: 'stale-baseline',
      message:
        `${BOUNDARY_CONFIG_PATH} accepts { file: '${entry.file}', import: '${entry.import}' }, but that violation no ` +
        'longer exists: delete that entry from the baseline.'
    });
  }
  return { ok: problems.length === 0, problems };
}
