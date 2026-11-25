import test from 'node:test';
import assert from 'node:assert/strict';
import { isExternalLink, linkTargets, markdownLines } from '../src/markdown.mjs';

const kinds = (text) => markdownLines(text).map(({ kind }) => kind);

test('CRLF and LF text give the same numbered lines', () => {
  assert.deepEqual(markdownLines('a\r\nb\r\n'), markdownLines('a\nb\n'));
  assert.deepEqual(
    markdownLines('a\r\nb').map(({ line, text }) => [line, text]),
    [
      [1, 'a'],
      [2, 'b']
    ]
  );
});

test('a fence closes only on a marker of the same character and at least its length', () => {
  assert.deepEqual(kinds(['````md', '```', '~~~~', '`````', 'after'].join('\n')), [
    'fence',
    'code',
    'code',
    'fence',
    'prose'
  ]);
});

test('a marker followed by text does not close the fence', () => {
  assert.deepEqual(kinds(['```', '```js', '```'].join('\n')), ['fence', 'code', 'fence']);
});

test('link targets: inline, image, angle brackets, reference definition and HTML, in column order', () => {
  assert.deepEqual(
    linkTargets('<a href="b.md">b</a> [a](a.md "t") ![i](<i 1.png>)').map(({ target }) => target),
    ['b.md', 'a.md', 'i 1.png']
  );
  assert.deepEqual(
    linkTargets('[ref]: docs/x.md').map(({ target }) => target),
    ['docs/x.md']
  );
});

test('links in code spans and external links are not targets', () => {
  assert.deepEqual(linkTargets('`[x](gone.md)` [site](https://x.y) [m](mailto:a@b) [p](//cdn/x)'), []);
});

test('external links have a scheme or start with //', () => {
  for (const t of ['https://x', 'mailto:a@b', 'vscode://f', '//cdn/x']) assert.equal(isExternalLink(t), true, t);
  for (const t of ['docs/a.md', '#anchor', '../README.md', '/AGENTS.md']) assert.equal(isExternalLink(t), false, t);
});
