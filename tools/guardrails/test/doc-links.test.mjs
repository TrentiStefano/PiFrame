import test from 'node:test';
import assert from 'node:assert/strict';
import { checkDocLinks } from '../src/index.mjs';

const doc = (path, ...lines) => ({ path, contents: lines.join('\n') });

test('a link to a file that does not exist fails, naming the file, the line, the target and the fix', () => {
  const result = checkDocLinks({
    files: [doc('docs/guide.md', '# Guide', '', 'See [setup](setup.md) first.')],
    trackedFiles: ['docs/guide.md']
  });
  assert.equal(result.ok, false);
  assert.equal(result.broken.length, 1);
  const [broken] = result.broken;
  assert.equal(broken.file, 'docs/guide.md');
  assert.equal(broken.line, 3);
  assert.equal(broken.target, 'setup.md');
  assert.match(broken.message, /docs\/guide\.md:3/);
  assert.match(broken.message, /docs\/setup\.md/);
  assert.match(broken.message, /fix/i);
});

test('valid relative links pass: sibling, parent, folder, root-relative, image, encoded and reference-style', () => {
  const result = checkDocLinks({
    files: [
      doc(
        'docs/guide.md',
        '# Guide',
        'See [setup](./setup.md), [the readme](../README.md "title") and [tools](../tools/scripts/).',
        'Also ![shot](design/a%20shot.png), [root](/AGENTS.md) and [angle](<setup.md>).',
        '[ref]: setup.md'
      )
    ],
    trackedFiles: [
      'docs/guide.md',
      'docs/setup.md',
      'README.md',
      'AGENTS.md',
      'tools/scripts/check.mjs',
      'docs/design/a shot.png'
    ]
  });
  assert.deepEqual(result.broken, []);
  assert.equal(result.ok, true);
});

test('a link to a heading that does not exist fails, naming the anchor and the headings to choose from', () => {
  const result = checkDocLinks({
    files: [
      doc('docs/a.md', '# Title', '', 'Jump to [setup](#set-up) or [b](b.md#gone).'),
      doc('docs/b.md', '## Install')
    ],
    trackedFiles: ['docs/a.md', 'docs/b.md']
  });
  assert.deepEqual(
    result.broken.map((b) => [b.file, b.line, b.target]),
    [
      ['docs/a.md', 3, '#set-up'],
      ['docs/a.md', 3, 'b.md#gone']
    ]
  );
  assert.match(result.broken[0].message, /docs\/a\.md:3.*#set-up/);
  assert.match(result.broken[0].message, /#title/);
  assert.match(result.broken[1].message, /docs\/b\.md.*#install/);
});

test('links to existing headings pass, with GitHub anchors (punctuation, code, duplicates, explicit ids)', () => {
  const result = checkDocLinks({
    files: [
      doc(
        'docs/a.md',
        '# Local verification before a pull request',
        '## The inner loop: `check`',
        '## Notes',
        '## Notes',
        'Setext title',
        '============',
        '<a id="custom-anchor"></a>',
        '```',
        '# not a heading',
        '```',
        '[1](#local-verification-before-a-pull-request) [2](#the-inner-loop-check) [3](#notes-1)',
        '[4](#setext-title) [5](#custom-anchor) [6](b.md#escape-hatch-ratchet) [7](B.md)',
        '[8](../tools/x.mjs#L10) [9](#Notes)'
      ),
      doc('docs/b.md', '## Escape-hatch ratchet')
    ],
    trackedFiles: ['docs/a.md', 'docs/b.md', 'docs/B.md', 'tools/x.mjs']
  });
  assert.deepEqual(result.broken, []);
  const notAHeading = checkDocLinks({
    files: [doc('docs/a.md', '```', '# not a heading', '```', '[x](#not-a-heading)')],
    trackedFiles: ['docs/a.md']
  });
  assert.equal(notAHeading.ok, false);
});

test('only docs, README files and AGENTS.md are checked; other Markdown files only provide headings to link to', () => {
  const broken = '[x](gone.md)';
  const result = checkDocLinks({
    files: [
      doc('AGENTS.md', broken),
      doc('README.md', broken, '[log](CHANGELOG.md#151)'),
      doc('apps/pi_frame/README.md', broken),
      doc('tools/harness/readme.md', broken),
      doc('docs/adr/0001-x.md', broken),
      doc('CHANGELOG.md', '## 1.5.1', broken),
      doc('apps/pi_frame/DESIGN.md', broken),
      doc('.claude/skills/tdd/SKILL.md', broken)
    ],
    trackedFiles: ['CHANGELOG.md']
  });
  assert.deepEqual(result.broken.map((b) => b.file).sort(), [
    'AGENTS.md',
    'README.md',
    'apps/pi_frame/README.md',
    'docs/adr/0001-x.md',
    'tools/harness/readme.md'
  ]);
});

test('HTML src and href attributes are links too', () => {
  const result = checkDocLinks({
    files: [
      doc(
        'README.md',
        '<img src="docs/icon.png" alt=""> <a href="docs/security.md">x</a> <a href="https://example.com">y</a>',
        '<a href="LICENSE">l</a> <img src="docs/gone.png">'
      )
    ],
    trackedFiles: ['README.md', 'docs/icon.png', 'docs/security.md', 'LICENSE']
  });
  assert.deepEqual(
    result.broken.map((b) => [b.line, b.target]),
    [[2, 'docs/gone.png']]
  );
});

test('external URLs, mailto links and other schemes are ignored', () => {
  const result = checkDocLinks({
    files: [
      doc(
        'README.md',
        '[site](https://example.com/missing.md) [plain](http://x.y) [mail](mailto:a@b.c)',
        '[proto](//cdn.example.com/x.js) [vscode](vscode://file/x)'
      )
    ],
    trackedFiles: ['README.md']
  });
  assert.deepEqual(result.broken, []);
});

test('links inside fenced code blocks and inline code are ignored, links after the fence are checked', () => {
  const result = checkDocLinks({
    files: [
      doc(
        'docs/a.md',
        '```markdown',
        '[example](missing.md)',
        '```',
        '~~~',
        '[tilde](missing.md)',
        '~~~',
        '    ````text',
        '    [indented fence](missing.md)',
        '    ````',
        'Write `[x](missing.md)` to link.',
        '[real](gone.md)'
      )
    ],
    trackedFiles: ['docs/a.md']
  });
  assert.deepEqual(
    result.broken.map((b) => [b.line, b.target]),
    [[11, 'gone.md']]
  );
});

test('a broken reference-style link definition fails on its own line', () => {
  const result = checkDocLinks({
    files: [doc('README.md', 'Read the [guide][g].', '', '[g]: docs/gone.md')],
    trackedFiles: ['README.md']
  });
  assert.deepEqual(
    result.broken.map((b) => [b.line, b.target]),
    [[3, 'docs/gone.md']]
  );
});
