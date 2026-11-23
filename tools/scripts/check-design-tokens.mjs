#!/usr/bin/env node
/**
 * Design token match gate step: DESIGN.md's tokens (front matter plus the Motion table) must equal the shipped theme
 * (themes/*.json and packages/pi_frame_theme). Thin adapter: reads the files and prints what the pure
 * checkDesignTokens (tools/guardrails/src/design-tokens.mjs) reports. See docs/pr-verification.md.
 *
 *   node tools/scripts/check-design-tokens.mjs
 */
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';
import { checkDesignTokens, DESIGN_PATH, THEME_PACKAGE_FILES } from '../guardrails/src/index.mjs';
import { REPO } from './repo-files.mjs';

const read = (file) => ({ file, text: readFileSync(join(REPO, file), 'utf8') });

const { ok, problems } = checkDesignTokens({
  design: read(DESIGN_PATH).text,
  parseYaml: parse,
  themeFiles: readdirSync(join(REPO, 'themes')).map((name) => read(`themes/${name}`)),
  text: read(THEME_PACKAGE_FILES.text),
  motion: read(THEME_PACKAGE_FILES.motion),
  scale: read(THEME_PACKAGE_FILES.scale)
});
if (ok) {
  console.log(`✔ design token check: ${DESIGN_PATH}'s tokens match themes/ and packages/pi_frame_theme.`);
} else {
  console.error(`\n✖ design token check: ${problems.length} problem(s):\n`);
  for (const p of problems) console.error(`- ${p.message}`);
  process.exit(1);
}
