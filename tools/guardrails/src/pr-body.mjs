/**
 * PR-body check: a pull request body must have the review shape the template asks for (.github/pull_request_template.md):
 * a linked issue under Closes, non-empty Summary and Evidence, Merge Danger with Door and Blast Radius, Guardrail
 * changes that say "none" or describe the change, no leftover placeholder text, and no local absolute path (a Windows
 * drive path or a macOS or Linux home folder). Screenshots are not required.
 *
 * Pure: no I/O. tools/scripts/check-pr-body.mjs (run by .github/workflows/pr-body.yml, and by `pnpm run pr` before it
 * creates the pull request) reads the body and calls it. See docs/pr-verification.md#pr-body-check.
 */
import { markdownLines, normalizeLineEndings } from './markdown.mjs';

/** The template every pull request body starts from, relative to the repository root. */
export const PR_TEMPLATE_PATH = '.github/pull_request_template.md';

/** Template hints are HTML comments: they are not content, so an untouched template fails every section. */
const HTML_COMMENT = /<!--[\s\S]*?-->/g;
/**
 * Placeholder text left behind when the template is copied without being filled in: the angle-bracket values of
 * .github/pull_request_template.md, and a line that starts with a TODO-style marker. A word such as TODO inside a
 * sentence is content, not a placeholder.
 */
const TEMPLATE_PLACEHOLDERS = ['<one-way or two-way>', '<one word>'];
const LEFTOVER_MARKER = /^\s*(?:[-*]\s+)?(?:TODO|TBD|FIXME)\s*:/i;
/**
 * A local absolute path: a Windows drive path (`C:\...`, `D:/...`) or a macOS or Linux home folder (`/Users/...`,
 * `/home/...`). It names the author's machine and user, and no reader can open it. The drive letter must not follow a
 * letter or digit, so `https://` is not one.
 */
const LOCAL_PATH = /(?<![A-Za-z0-9])[A-Za-z]:[\\/][^\s`'")]*|(?<![\w.~-])\/(?:Users|home)\/[^\s`'")]+/;
const ISSUE_REFERENCE = /#\d+\b|github\.com\/[^\s)]+\/(?:issues|pull)\/\d+/;
/** Door is exactly one-way or two-way; an explanation may follow after a space or a punctuation mark. */
const DOOR = /^(?:one-way|two-way)(?=$|[\s.,;:(—–-])/i;
/** Blast Radius names what breaks: one word or a short phrase of words, never a single character. */
const BLAST_RADIUS = /^[A-Za-z][A-Za-z-]+(?: [A-Za-z][A-Za-z-]*){0,2}\.?$/;
/** Summary, Evidence and Guardrail changes need a sentence, not a fragment. `none` is the one short answer allowed. */
const MIN_WORDS = 4;

/** The number of words in a section's text, ignoring Markdown bullets and punctuation-only tokens. */
function wordCount(text) {
  return text.split(/\s+/).filter((word) => /[A-Za-z0-9]/.test(word)).length;
}

/**
 * The text of each `## ` section, keyed by its lower-case heading. A heading inside a code fence is part of the
 * section, not a new one, as in the rest of the guardrail Markdown reading.
 *
 * @param {string} text the body with HTML comments removed
 * @returns {Map<string, string>}
 */
function sectionsOf(text) {
  const lines = new Map();
  let current;
  for (const { text: line, kind } of markdownLines(text)) {
    const heading = kind === 'prose' ? line.match(/^##\s+(.+?)\s*$/) : null;
    if (heading) {
      current = heading[1].trim().toLowerCase();
      lines.set(current, []);
    } else if (current) {
      lines.get(current).push(line);
    }
  }
  return new Map([...lines].map(([name, body]) => [name, body.join('\n').trim()]));
}

/**
 * @param {string} body the pull request body as written (Markdown, CRLF or LF)
 * @returns {{ ok: boolean, problems: string[] }} one entry per missing part, each naming what to write
 */
export function checkPrBody(body) {
  const text = normalizeLineEndings(body).replace(HTML_COMMENT, '');
  const sections = sectionsOf(text);
  const section = (name) => sections.get(name.toLowerCase()) ?? '';
  const problems = [];

  if (!ISSUE_REFERENCE.test(section('Closes'))) {
    problems.push('Closes: link the issue this pull request closes or refers to (for example `#81`).');
  }
  const summary = section('Summary');
  if (!summary) problems.push('Summary is empty: say what the pull request changes and why.');
  else if (wordCount(summary) < MIN_WORDS) {
    problems.push(`Summary is too short: write at least ${MIN_WORDS} words saying what changes and why.`);
  }
  const evidence = section('Evidence');
  if (!evidence) problems.push('Evidence is empty: show the before and after (text output or a real screenshot).');
  else if (wordCount(evidence) < MIN_WORDS) {
    problems.push(
      `Evidence is too short: show the before and after in at least ${MIN_WORDS} words, or a real screenshot.`
    );
  }

  const mergeDanger = section('Merge Danger');
  const door = mergeDanger.match(/\*\*Door:\*\*[ \t]*(.*)$/im)?.[1].trim() ?? '';
  if (!DOOR.test(door)) problems.push('Merge Danger: write `**Door:** one-way` or `**Door:** two-way`.');
  const blastRadius = mergeDanger.match(/\*\*Blast Radius:\*\*[ \t]*(.*)$/im)?.[1].trim() ?? '';
  if (!BLAST_RADIUS.test(blastRadius)) {
    problems.push('Merge Danger: write `**Blast Radius:** <one word>`, for example `workflow` or `daemon`.');
  }

  const guardrails = section('Guardrail changes');
  if (!guardrails) problems.push('Guardrail changes is empty: write `none`, or describe the guardrail change.');
  else if (!/^none\.?$/i.test(guardrails) && wordCount(guardrails) < MIN_WORDS) {
    problems.push(`Guardrail changes is too short: write \`none\`, or a sentence of at least ${MIN_WORDS} words.`);
  }

  const placeholder = text
    .split('\n')
    .find(
      (line) => LEFTOVER_MARKER.test(line) || TEMPLATE_PLACEHOLDERS.some((hint) => line.toLowerCase().includes(hint))
    );
  if (placeholder !== undefined) {
    problems.push(
      `Leftover placeholder text in the body: \`${placeholder.trim()}\`. Replace it with the real content.`
    );
  }

  // The raw body, code fences included: the whole body is public.
  const localPath = normalizeLineEndings(body).match(LOCAL_PATH)?.[0];
  if (localPath !== undefined) {
    problems.push(
      `Local path in the body: \`${localPath}\`. Use a path relative to the repository, or just the file name.`
    );
  }

  return { ok: problems.length === 0, problems };
}
