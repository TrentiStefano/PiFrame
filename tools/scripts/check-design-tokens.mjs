#!/usr/bin/env node
/**
 * Design token match gate step: DESIGN.md's front-matter tokens must equal the shipped theme (themes/*.json and
 * packages/pi_frame_theme). Thin adapter: reads the files and prints what the pure designTokenMatch reports.
 */
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';
import { designTokenMatch, motionTable, themeTokenSources } from '../guardrails/src/index.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (file) => readFileSync(join(root, file), 'utf8').replace(/\r\n/g, '\n');

const markdown = read('DESIGN.md');
const frontMatter = markdown.match(/^---\n([\s\S]*?)\n---\n/);
if (!frontMatter) {
  console.error('DESIGN.md has no YAML front matter (a block between two "---" lines at the top).');
  process.exit(1);
}
// Motion is a table in the Motion section until the pinned linter accepts the spec's motion group (see motionTable).
const design = { ...parse(frontMatter[1]), motion: motionTable(markdown) };

const themes = readdirSync(join(root, 'themes'))
  .filter((name) => name.endsWith('.json') && !name.endsWith('.schema.json'))
  .sort()
  .map((name) => ({ file: `themes/${name}`, theme: JSON.parse(read(`themes/${name}`)) }));
const dart = (name) => {
  const file = `packages/pi_frame_theme/lib/src/${name}`;
  return { file, text: read(file) };
};
const sources = themeTokenSources({
  themes,
  text: dart('theme_text.dart'),
  motion: dart('theme_motion.dart'),
  scale: dart('theme_scale.dart')
});

const mismatches = designTokenMatch({ design, sources });
if (mismatches.length > 0) {
  console.error(`DESIGN.md tokens differ from the theme (${mismatches.length}):`);
  for (const { message } of mismatches) console.error(`  - ${message}`);
  console.error('The theme files and packages/pi_frame_theme are the source of truth: update DESIGN.md to match.');
  process.exit(1);
}
const count = sources.reduce((n, { tokens }) => n + Object.keys(tokens).length, 0);
console.log(`DESIGN.md tokens match the theme (${count} values from ${sources.length} files).`);
