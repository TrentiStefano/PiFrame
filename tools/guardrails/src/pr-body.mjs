/**
 * PR-body check: a pull request body must have the review shape the template asks for (.github/pull_request_template.md):
 * a linked issue under Closes, non-empty Summary and Evidence, Merge Danger with Door and Blast Radius, Guardrail
 * changes that say "none" or describe the change, and no leftover placeholder text. Screenshots are not required.
 *
 * Pure: no I/O. tools/scripts/check-pr-body.mjs (run by .github/workflows/pr-body.yml, and by `pnpm run pr` before it
 * creates the pull request) reads the body and calls it. See docs/pr-verification.md#pr-body-check.
 */
import { markdownLines, normalizeLineEndings } from './markdown.mjs';

/** The template every pull request body starts from, relative to the repository root. */
export const PR_TEMPLATE_PATH = '.github/pull_request_template.md';

/** Template hints are HTML comments: they are not content, so an untouched template fails every section. */
const HTML_COMMENT = /<!--[\s\S]*?-->/g;
/** Placeholder text the template leaves behind when it is copied without being filled in. */
const PLACEHOLDER =
  /\bTODO\b|\bTBD\b|\bFIXME\b|\{\{[^}]*\}\}|<(?:placeholder|fill in|one-way or two-way|one word|issue|spec)[^>]*>/i;
const ISSUE_REFERENCE = /#\d+\b|github\.com\/[^\s)]+\/(?:issues|pull)\/\d+/;
const DOOR = /^(?:one-way|two-way)\b/i;
const ONE_WORD = /^[A-Za-z][\w-]*\.?$/;

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
  if (!section('Summary')) problems.push('Summary is empty: say what the pull request changes and why.');
  if (!section('Evidence'))
    problems.push('Evidence is empty: show the before and after (text output or a real screenshot).');

  const mergeDanger = section('Merge Danger');
  const door = mergeDanger.match(/\*\*Door:\*\*[ \t]*(.*)$/im)?.[1].trim() ?? '';
  if (!DOOR.test(door)) problems.push('Merge Danger: write `**Door:** one-way` or `**Door:** two-way`.');
  const blastRadius = mergeDanger.match(/\*\*Blast Radius:\*\*[ \t]*(.*)$/im)?.[1].trim() ?? '';
  if (!ONE_WORD.test(blastRadius)) {
    problems.push('Merge Danger: write `**Blast Radius:** <one word>`, for example `workflow` or `daemon`.');
  }

  const guardrails = section('Guardrail changes');
  if (!guardrails) problems.push('Guardrail changes is empty: write `none`, or describe the guardrail change.');

  const placeholder = text.split('\n').find((line) => PLACEHOLDER.test(line));
  if (placeholder !== undefined) {
    problems.push(
      `Leftover placeholder text in the body: \`${placeholder.trim()}\`. Replace it with the real content.`
    );
  }

  return { ok: problems.length === 0, problems };
}
