/**
 * Agent map check: AGENTS.md is a short map, and every path and command it names must exist.
 *
 * Pure: no I/O. tools/scripts/check-agent-map.mjs reads AGENTS.md, the tracked files and the root package.json
 * scripts, and calls it.
 */

/** The map the check reads, relative to the repository root. */
export const AGENT_MAP_PATH = 'AGENTS.md';
/** Longer than this and the map is turning back into an encyclopedia: move detail into a doc it points at. */
export const AGENT_MAP_MAX_LINES = 100;

/**
 * @param {object} input
 * @param {string} input.text the AGENTS.md text
 * @param {string[]} input.paths tracked repository files (and folders), `/`-separated, relative to the root
 * @param {string[]} input.scripts the root package.json script names
 * @returns {{ ok: boolean, violations: { line: number, message: string }[] }}
 */
export function checkAgentMap({ text, paths, scripts }) {
  const known = new Set(scripts);
  const lines = text.replace(/\r\n/g, '\n').replace(/\n$/, '').split('\n');
  const violations = [];
  if (lines.length > AGENT_MAP_MAX_LINES) {
    violations.push({
      line: AGENT_MAP_MAX_LINES + 1,
      message:
        `${AGENT_MAP_PATH} has ${lines.length} lines, over the limit of ${AGENT_MAP_MAX_LINES}. ` +
        'Keep it a map: move detail into a doc and point at it.'
    });
  }

  const exists = existenceCheck(paths);
  let fenced = false;
  lines.forEach((content, index) => {
    const line = index + 1;
    if (/^\s*(```|~~~)/.test(content)) {
      fenced = !fenced;
      return;
    }
    for (const path of mentionedPaths(content, fenced)) {
      if (!exists(path)) {
        violations.push({
          line,
          message:
            `${AGENT_MAP_PATH}:${line} names \`${path}\`, which matches no tracked file or folder. ` +
            'Fix the path or remove the mention.'
        });
      }
    }
    for (const [, script] of content.matchAll(/\bpnpm run ([\w:.-]*[\w:-])/g)) {
      if (!known.has(script)) {
        violations.push({
          line,
          message:
            `${AGENT_MAP_PATH}:${line} runs \`pnpm run ${script}\`, but the root package.json has no "${script}" ` +
            'script. Fix the command or add the script.'
        });
      }
    }
  });
  return { ok: violations.length === 0, violations };
}

/** @returns {(path: string) => boolean} true when the path (or glob) names a tracked file or one of their folders. */
function existenceCheck(paths) {
  const files = paths.map((p) => p.replaceAll('\\', '/').replace(/\/$/, ''));
  const known = new Set(files);
  for (const file of files) {
    for (let i = file.indexOf('/'); i !== -1; i = file.indexOf('/', i + 1)) known.add(file.slice(0, i));
  }
  const all = [...known];
  return (path) => {
    const target = path.replace(/\/$/, '');
    if (!target.includes('*')) return known.has(target);
    const glob = new RegExp(
      `^${target
        .split(/(\*\*\/|\*\*|\*)/)
        .map((part) =>
          part === '**/'
            ? '(?:.*/)?'
            : part === '**'
              ? '.*'
              : part === '*'
                ? '[^/]*'
                : part.replace(/[.+?^${}()|[\]\\]/g, '\\$&')
        )
        .join('')}$`
    );
    // Without a folder, a glob is a file-name pattern (`*_test.dart`) and matches in any folder.
    const subject = target.includes('/') ? (p) => p : (p) => p.slice(p.lastIndexOf('/') + 1);
    return all.some((p) => glob.test(subject(p)));
  };
}

/**
 * The repository paths a line names: tokens in inline code spans (every token, inside a fenced block) and relative
 * link targets, in the order they appear. A token is a path when it has a `/` or ends in a file extension; URLs,
 * home (`~/`) and absolute paths, slash commands, flags, `<placeholders>`, `@scoped/packages` and numbers are not.
 */
function mentionedPaths(content, fenced) {
  /** @type {{ at: number, path: string }[]} */
  const found = [];
  const addTokens = (span, at) => {
    for (const token of span.split(/\s+/)) {
      const path = token.replace(/^[("']+/, '').replace(/[),;:.'"]+$/, '');
      if (isPathToken(path)) found.push({ at, path });
    }
  };
  if (fenced) addTokens(content, 0);
  else {
    for (const m of content.matchAll(/`([^`]+)`/g)) addTokens(m[1], m.index);
    for (const m of content.matchAll(/\]\(([^)\s]+)\)/g)) {
      const target = m[1].replace(/#.*$/, '');
      if (target && !/^[a-z][\w+.-]*:/i.test(target)) found.push({ at: m.index, path: target });
    }
  }
  return found.sort((a, b) => a.at - b.at).map(({ path }) => path);
}

function isPathToken(token) {
  if (!token || /^[-~@$/<]/.test(token) || /[<>=]|:\/\//.test(token)) return false;
  return token.includes('/') || /\.[a-z][a-z0-9]*$/i.test(token);
}
