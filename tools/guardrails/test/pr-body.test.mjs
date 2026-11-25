import test from 'node:test';
import assert from 'node:assert/strict';
import { checkPrBody } from '../src/pr-body.mjs';

/** A complete body, as the PR template asks for it. Each test replaces one part of it. */
const COMPLETE = `## Closes

Closes #81 (spec #80).

## Summary

Adds the PR template and the body check.

## Evidence

- Before: \`pnpm run pr\` opened a PR with \`--fill\`.
- After: the check refuses a body without Merge Danger (see the attached output).

## Merge Danger

- **Door:** two-way
- **Blast Radius:** workflow

## Guardrail changes

none
`;

const replaceSection = (body, heading, content) =>
  body.replace(new RegExp(`(## ${heading}\\n)[\\s\\S]*?(?=\\n## |$)`), `$1\n${content}\n`);

const problemsOf = (body) => checkPrBody(body).problems;

test('a complete body passes with no problems', () => {
  assert.deepEqual(checkPrBody(COMPLETE), { ok: true, problems: [] });
});

test('a body without any image passes: screenshots are not required', () => {
  assert.equal(COMPLETE.includes('!['), false);
  assert.equal(checkPrBody(COMPLETE).ok, true);
});

test('a body with no linked issue is refused', () => {
  const body = replaceSection(COMPLETE, 'Closes', 'Adds the template.');
  assert.equal(checkPrBody(body).ok, false);
  assert.match(problemsOf(body).join('\n'), /Closes.*issue/);
});

test('a linked issue given as a URL counts', () => {
  const body = replaceSection(COMPLETE, 'Closes', 'https://github.com/TrentiStefano/PiFrame/issues/81');
  assert.equal(checkPrBody(body).ok, true);
});

test('a missing Closes section is refused', () => {
  const body = COMPLETE.replace(/## Closes\n[\s\S]*?(?=## Summary)/, '');
  assert.match(problemsOf(body).join('\n'), /Closes/);
});

test('an empty Summary is refused', () => {
  const body = replaceSection(COMPLETE, 'Summary', '');
  assert.match(problemsOf(body).join('\n'), /Summary is empty/);
});

test('an empty Evidence is refused', () => {
  const body = replaceSection(COMPLETE, 'Evidence', '<!-- hint only -->');
  assert.match(problemsOf(body).join('\n'), /Evidence is empty/);
});

test('a missing Merge Danger section is refused', () => {
  const body = COMPLETE.replace(/## Merge Danger\n[\s\S]*?(?=## Guardrail)/, '');
  assert.match(problemsOf(body).join('\n'), /Merge Danger/);
});

test('Merge Danger without Door is refused', () => {
  const body = COMPLETE.replace('- **Door:** two-way\n', '');
  assert.match(problemsOf(body).join('\n'), /Door/);
});

test('Door must say one-way or two-way', () => {
  const body = COMPLETE.replace('**Door:** two-way', '**Door:** sometimes');
  assert.match(problemsOf(body).join('\n'), /Door/);
});

test('Merge Danger without Blast Radius is refused', () => {
  const body = COMPLETE.replace('- **Blast Radius:** workflow\n', '');
  assert.match(problemsOf(body).join('\n'), /Blast Radius/);
});

test('Blast Radius must be one word', () => {
  const body = COMPLETE.replace('**Blast Radius:** workflow', '**Blast Radius:** the whole app and the daemon');
  assert.match(problemsOf(body).join('\n'), /Blast Radius/);
});

test('Guardrail changes: none passes, a description passes, empty is refused', () => {
  assert.equal(checkPrBody(COMPLETE).ok, true);
  const described = replaceSection(
    COMPLETE,
    'Guardrail changes',
    'Raises nothing; adds a PR body check to approval paths.'
  );
  assert.equal(checkPrBody(described).ok, true);
  const empty = replaceSection(COMPLETE, 'Guardrail changes', '');
  assert.match(problemsOf(empty).join('\n'), /Guardrail changes/);
});

test('Guardrail changes: None (any case, with a full stop) counts as none', () => {
  const body = replaceSection(COMPLETE, 'Guardrail changes', 'None.');
  assert.equal(checkPrBody(body).ok, true);
});

test('a leftover placeholder is refused', () => {
  const body = COMPLETE.replace('Adds the PR template and the body check.', 'TODO: describe the change');
  assert.match(problemsOf(body).join('\n'), /placeholder/);
  const angle = COMPLETE.replace('**Blast Radius:** workflow', '**Blast Radius:** <one word>');
  assert.match(problemsOf(angle).join('\n'), /placeholder/);
});

test('HTML comments (the template hints) are not content: a body with only hints fails every section', () => {
  const hintsOnly = `## Closes

<!-- Link the spec and tickets. -->

## Summary

<!-- What changes and why. -->

## Evidence

<!-- Before and after. -->

## Merge Danger

<!-- **Door:** one-way or two-way -->

## Guardrail changes

<!-- none, or describe the change. -->
`;
  const problems = problemsOf(hintsOnly).join('\n');
  assert.match(problems, /Closes/);
  assert.match(problems, /Summary is empty/);
  assert.match(problems, /Evidence is empty/);
  assert.match(problems, /Door/);
  assert.match(problems, /Guardrail changes/);
});

test('a heading inside a code fence is not a section', () => {
  const body = replaceSection(COMPLETE, 'Summary', '```md\n## Evidence\n```\n\nReal summary.');
  assert.equal(checkPrBody(body).ok, true);
});

test('CRLF bodies are read the same as LF bodies', () => {
  assert.deepEqual(checkPrBody(COMPLETE.replace(/\n/g, '\r\n')), checkPrBody(COMPLETE));
});

test('every missing part is named, not just the first', () => {
  const problems = problemsOf('## Summary\n\n## Evidence\n\n');
  assert.ok(problems.length >= 4, problems.join('\n'));
});
