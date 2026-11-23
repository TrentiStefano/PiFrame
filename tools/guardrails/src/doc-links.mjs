/**
 * The doc link check. Finds relative links in Markdown files that point at a file that is not tracked.
 *
 * Pure: no I/O. tools/scripts/check-doc-links.mjs reads the tracked files and calls it.
 */
import { linkTargets, markdownLines } from './markdown.mjs';
import { toPosix } from './paths.mjs';

const MARKDOWN = /\.md$/i;

/** Each line of Markdown outside fenced code blocks, as [line number, text]. */
const proseLines = (contents) =>
  markdownLines(contents)
    .filter(({ kind }) => kind === 'prose')
    .map(({ line, text }) => [line, text]);

const ATX_HEADING = /^ {0,3}#{1,6}(?:\s+(.*?))?(?:\s+#+)?\s*$/;
const SETEXT_UNDERLINE = /^ {0,3}(=+|-+)\s*$/;
const HTML_ID = /<[a-z][^>]*?\s(?:id|name)\s*=\s*["']([^"']+)["']/gi;

/** GitHub's heading anchor: inline Markdown dropped, lower case, punctuation removed, spaces as hyphens. */
function slug(heading) {
  return heading
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/<[^>]+>/g, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{M}\p{N}\p{Pc} -]/gu, '')
    .replace(/ /g, '-');
}

/** Every anchor a Markdown file defines: its headings (duplicates numbered as GitHub does) and explicit ids. */
function anchorsOf(contents) {
  const anchors = new Set();
  const seen = new Map();
  const add = (heading) => {
    const base = slug(heading.trim());
    const count = seen.get(base) ?? 0;
    seen.set(base, count + 1);
    anchors.add(count === 0 ? base : `${base}-${count}`);
  };
  const lines = proseLines(contents);
  lines.forEach(([number, text], i) => {
    for (const m of text.matchAll(HTML_ID)) anchors.add(m[1].toLowerCase());
    const atx = text.match(ATX_HEADING);
    if (atx) return add(atx[1] ?? '');
    const next = lines[i + 1];
    if (next && next[0] === number + 1 && SETEXT_UNDERLINE.test(next[1]) && text.trim() && !/^\s{4}/.test(text)) {
      add(text);
    }
  });
  return anchors;
}

function decode(target) {
  try {
    return decodeURIComponent(target);
  } catch {
    return target;
  }
}

/** Resolves `target` against the folder of `from` (or the root, for `/...`); null when it climbs above the root. */
function resolve(from, target) {
  const parts = target.startsWith('/') ? [] : from.split('/').slice(0, -1);
  for (const segment of target.split('/')) {
    if (segment === '' || segment === '.') continue;
    if (segment === '..') {
      if (parts.length === 0) return null;
      parts.pop();
    } else parts.push(segment);
  }
  return parts.join('/');
}

/** The root files agents read as context; their links are checked like the docs. */
const ROOT_AGENT_CONTEXT = new Set(['AGENTS.md', 'GLOSSARY.md', 'DESIGN.md']);

/** The files whose links are checked: every Markdown file under docs/, every README.md and the root agent context. */
export function inDocLinkScope(path) {
  const p = toPosix(path);
  return (p.startsWith('docs/') && MARKDOWN.test(p)) || /(^|\/)readme\.md$/i.test(p) || ROOT_AGENT_CONTEXT.has(p);
}

/**
 * @param {object} input
 * @param {{ path: string, contents: string }[]} input.files every tracked Markdown file: the ones in scope
 *   (inDocLinkScope) have their links checked, all of them provide the headings a link can point at
 * @param {string[]} input.trackedFiles every tracked file in the repository
 * @returns {{ ok: boolean, problems: { file: string, line: number, target: string, message: string }[] }} `message`
 *   names the file, the line and the missing target, and says how to fix it
 */
export function checkDocLinks({ files, trackedFiles }) {
  const tracked = new Set(trackedFiles.map(toPosix));
  const folders = new Set(
    [...tracked].flatMap((p) =>
      p
        .split('/')
        .slice(0, -1)
        .map((_, i, parts) => parts.slice(0, i + 1).join('/'))
    )
  );
  const contents = new Map(files.map((f) => [toPosix(f.path), f.contents]));
  const anchorCache = new Map();
  const anchors = (path) => {
    if (!anchorCache.has(path)) anchorCache.set(path, anchorsOf(contents.get(path) ?? ''));
    return anchorCache.get(path);
  };

  const problems = [];
  for (const [path, text] of contents) {
    if (!inDocLinkScope(path)) continue;
    for (const [line, prose] of proseLines(text)) {
      for (const { target } of linkTargets(prose)) {
        const problem = linkProblem(path, target, { tracked, folders, anchors });
        if (problem)
          problems.push({ file: path, line, target, message: `${path}:${line}: the link "${target}" ${problem}` });
      }
    }
  }
  return { ok: problems.length === 0, problems };
}

/** Why `target`, linked from `from`, is broken (with how to fix it), or null when it is fine. */
function linkProblem(from, target, { tracked, folders, anchors }) {
  const hash = target.indexOf('#');
  const filePart = decode(hash === -1 ? target : target.slice(0, hash));
  const fragment = hash === -1 ? null : decode(target.slice(hash + 1));
  const resolved = filePart === '' ? from : resolve(from, filePart);
  if (resolved === null) {
    return 'climbs above the repository root. To fix it, remove the extra "../" so it points at a tracked file.';
  }
  if (!tracked.has(resolved) && !folders.has(resolved)) {
    return (
      `points at ${resolved}, which is not a tracked file or folder. To fix it, point the link at where that ` +
      'file is now (relative to the linking file), or remove the link if the file was deleted.'
    );
  }
  // Anchors are checked in Markdown files only: a `#L10` on a source file is a GitHub line link.
  if (!fragment || !MARKDOWN.test(resolved)) return null;
  const known = anchors(resolved);
  if (known.has(fragment.toLowerCase())) return null;
  const choices = [...known].map((a) => `#${a}`);
  return (
    `points at the heading #${fragment} in ${resolved}, which has no such heading. To fix it, use one of its ` +
    `anchors (${choices.length ? choices.join(', ') : 'it has no headings'}), or link to the file without "#".`
  );
}
