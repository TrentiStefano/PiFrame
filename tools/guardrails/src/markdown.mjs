/**
 * Markdown reading shared by the guardrail checks (doc links, agent map, design tokens). Pure: no I/O.
 */

/** The text with every line ending as `\n` (Windows checkouts have CRLF files). */
export const normalizeLineEndings = (text) => text.replace(/\r\n?/g, '\n');

/** A code fence: three or more backticks or tildes (indented too, as inside list items). Group 1 is the marker. */
const FENCE = /^\s*(`{3,}|~{3,})/;

/**
 * Each line of the text, numbered from 1, with its place in the document: `prose`, a `fence` line (opening or
 * closing a fenced code block), or `code` (inside one). A fence closes only on a line that is just a marker of the
 * same character and at least the same length, as CommonMark has it.
 *
 * @param {string} text
 * @returns {{ line: number, text: string, kind: 'prose' | 'fence' | 'code' }[]}
 */
export function markdownLines(text) {
  let fence = null;
  return normalizeLineEndings(text)
    .split('\n')
    .map((content, index) => {
      const marker = content.match(FENCE)?.[1];
      let kind;
      if (fence) {
        const closes = marker && marker[0] === fence[0] && marker.length >= fence.length && content.trim() === marker;
        kind = closes ? 'fence' : 'code';
        if (closes) fence = null;
      } else if (marker) {
        kind = 'fence';
        fence = marker;
      } else {
        kind = 'prose';
      }
      return { line: index + 1, text: content, kind };
    });
}

/** A target with a scheme (`https:`, `mailto:`, `vscode:`) or protocol-relative (`//host`): not a repository path. */
const EXTERNAL = /^(?:[a-z][a-z0-9+.-]*:|\/\/)/i;

/** True when a link target points outside the repository (a URL or another scheme). */
export const isExternalLink = (target) => EXTERNAL.test(target);

/** `[text](target "title")` and `![alt](target)`: group 1 is `<target>` or a bare target. */
const INLINE_LINK = /!?\[[^\]]*\]\(\s*(<[^>]*>|[^)\s]+)[^)]*\)/g;
/** `[label]: target "title"` at the start of a line. */
const REFERENCE_DEFINITION = /^ {0,3}\[[^\]]+\]:\s*(<[^>]*>|\S+)/;
/** `<img src="...">` and `<a href="...">`: group 1 is the target. */
const HTML_LINK = /<[a-z][^>]*?\s(?:src|href)\s*=\s*["']([^"']*)["']/gi;
/** An inline code span: a run of backticks, its contents, and a run of the same length. */
const CODE_SPAN = /(`+)[\s\S]*?\1/g;

/**
 * The relative link targets on one line of prose, in the order they appear: inline links and images, a reference
 * definition, and HTML `src`/`href`. Code spans and external targets are left out; `<target>` loses its brackets.
 *
 * @param {string} line
 * @returns {{ target: string, at: number }[]} `at` is the column where the link starts
 */
export function linkTargets(line) {
  // Blank code spans out instead of deleting them, so the columns still match the line.
  const text = line.replace(CODE_SPAN, (span) => ' '.repeat(span.length));
  const found = [...text.matchAll(INLINE_LINK), ...text.matchAll(HTML_LINK)].map((m) => ({
    target: m[1],
    at: m.index
  }));
  const definition = text.match(REFERENCE_DEFINITION);
  if (definition) found.push({ target: definition[1], at: definition.index });
  return found
    .map(({ target, at }) => ({
      target: target.startsWith('<') && target.endsWith('>') ? target.slice(1, -1) : target,
      at
    }))
    .filter(({ target }) => !isExternalLink(target))
    .sort((a, b) => a.at - b.at);
}
