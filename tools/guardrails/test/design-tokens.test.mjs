import test from 'node:test';
import assert from 'node:assert/strict';
import { parse } from 'yaml';
import { checkDesignTokens, designTokenMatch, motionTable, themeTokenSources } from '../src/index.mjs';

const DARK = 'themes/piframe-dark.json';

const design = {
  version: 'alpha',
  name: 'PiFrame',
  colors: { dark: { primary: '#5F9FC5', surface: '#1c2432' } },
  rounded: { sm: '6px' },
  components: { 'button-primary': { backgroundColor: '{colors.dark.primary}' } }
};
const sources = [
  {
    file: DARK,
    tokens: { 'colors.dark.primary': '#5f9fc5', 'colors.dark.surface': '#1c2432', 'rounded.sm': '6px' }
  }
];

test('design tokens equal to the theme values match', () => {
  assert.deepEqual(designTokenMatch({ design, sources }), { ok: true, problems: [] });
});

test('a theme color that differs from DESIGN.md fails, naming the token, both values and the theme file', () => {
  const changed = [{ file: DARK, tokens: { ...sources[0].tokens, 'colors.dark.surface': '#ff0000' } }];
  const [mismatch, ...rest] = designTokenMatch({ design, sources: changed }).problems;
  assert.deepEqual(rest, []);
  assert.equal(mismatch.token, 'colors.dark.surface');
  assert.equal(mismatch.design, '#1c2432');
  assert.equal(mismatch.theme, '#ff0000');
  assert.equal(mismatch.file, DARK);
  for (const part of ['colors.dark.surface', '#1c2432', '#ff0000', DARK]) assert.ok(mismatch.message.includes(part));
});

test('a theme token that DESIGN.md does not define fails, naming the theme file', () => {
  const extra = [{ file: DARK, tokens: { ...sources[0].tokens, 'colors.dark.border': '#2e3c53' } }];
  const [mismatch, ...rest] = designTokenMatch({ design, sources: extra }).problems;
  assert.deepEqual(rest, []);
  assert.equal(mismatch.token, 'colors.dark.border');
  assert.equal(mismatch.design, undefined);
  assert.equal(mismatch.theme, '#2e3c53');
  assert.equal(mismatch.file, DARK);
  for (const part of ['colors.dark.border', '#2e3c53', DARK]) assert.ok(mismatch.message.includes(part));
});

test('a DESIGN.md token that no theme file defines fails', () => {
  const withExtra = { ...design, spacing: { gutter: '48px' } };
  const [mismatch, ...rest] = designTokenMatch({ design: withExtra, sources }).problems;
  assert.deepEqual(rest, []);
  assert.equal(mismatch.token, 'spacing.gutter');
  assert.equal(mismatch.design, '48px');
  assert.equal(mismatch.theme, undefined);
  for (const part of ['spacing.gutter', '48px', DARK]) assert.ok(mismatch.message.includes(part));
});

const TEXT = 'packages/pi_frame_theme/lib/src/theme_text.dart';
const MOTION = 'packages/pi_frame_theme/lib/src/theme_motion.dart';
const SCALE = 'packages/pi_frame_theme/lib/src/theme_scale.dart';

test('theme sources: theme JSON colors, radii, motion and fonts, and the theme package constants', () => {
  const theme = {
    variant: 'dark',
    colors: { accent: '#5F9FC5', accentContrast: '#0b1118', textPrimary: '#f8fafc' },
    syntax: { keyword: '#5f9fc5' },
    typography: {
      uiFontFamily: 'SchibstedGrotesk',
      headingFontFamily: 'BarlowCondensed',
      monoFontFamily: 'SourceCodePro'
    },
    radii: { sm: 6.0, pill: 999.0 },
    motion: { fast: 120, normal: 240 }
  };
  const text = [
    '      caption: _style(ui, 11, 16),',
    '      label: _style(ui, 12, 16, weight: FontWeight.w500),',
    '      monoBody: _style(code, 13, 20),'
  ].join('\n');
  const motion = [
    '  static const Duration instant = Duration.zero;',
    '  static const Duration micro = Duration(milliseconds: 120);',
    '  static const Duration panel = Duration(milliseconds: 240);',
    '  static const Cubic enterCurve = Cubic(0.23, 1, 0.32, 1);'
  ].join('\n');
  const scale = [
    'abstract final class FrameSpace {',
    '  static const double x1 = 4;',
    '  static const double x12 = 48;',
    '}',
    'abstract final class FrameSize {',
    '  static const double rowList = 28;',
    '}'
  ].join('\n');

  const sources = themeTokenSources({
    themes: [{ file: DARK, theme }],
    text: { file: TEXT, text },
    motion: { file: MOTION, text: motion },
    scale: { file: SCALE, text: scale }
  });
  const byFile = Object.fromEntries(sources.map((s) => [s.file, s.tokens]));

  assert.deepEqual(byFile[DARK], {
    'colors.dark.primary': '#5F9FC5',
    'colors.dark.on-primary': '#0b1118',
    'colors.dark.text-primary': '#f8fafc',
    'colors.dark.syntax-keyword': '#5f9fc5',
    'rounded.sm': '6px',
    'rounded.pill': '999px',
    'motion.micro.duration': '120ms',
    'motion.panel.duration': '240ms',
    'typography.brand-heading.fontFamily': 'BarlowCondensed',
    'typography.caption.fontFamily': 'SchibstedGrotesk',
    'typography.label.fontFamily': 'SchibstedGrotesk',
    'typography.mono-body.fontFamily': 'SourceCodePro'
  });
  assert.deepEqual(byFile[TEXT], {
    'typography.caption.fontSize': '11px',
    'typography.caption.lineHeight': '16px',
    'typography.caption.fontWeight': '400',
    'typography.label.fontSize': '12px',
    'typography.label.lineHeight': '16px',
    'typography.label.fontWeight': '500',
    'typography.mono-body.fontSize': '13px',
    'typography.mono-body.lineHeight': '20px',
    'typography.mono-body.fontWeight': '400'
  });
  assert.deepEqual(byFile[MOTION], {
    'motion.instant.duration': '0ms',
    'motion.micro.duration': '120ms',
    'motion.panel.duration': '240ms',
    'motion.enter-curve.timingFunction': 'cubic-bezier(0.23, 1, 0.32, 1)'
  });
  assert.deepEqual(byFile[SCALE], { 'spacing.x1': '4px', 'spacing.x12': '48px' });
});

test('a DESIGN.md token that references another token is an alias, not a theme value', () => {
  const withAlias = { ...design, colors: { primary: '{colors.dark.primary}', ...design.colors } };
  assert.deepEqual(designTokenMatch({ design: withAlias, sources }), { ok: true, problems: [] });
});

test('motion tokens are read from the Motion section table of DESIGN.md', () => {
  const markdown = [
    '## Layout',
    '',
    '| Token | Duration |',
    '| --- | --- |',
    '| `gutter` | 48px |',
    '',
    '## Motion',
    '',
    'Prose.',
    '',
    '| Token | Duration | Timing function | Used for |',
    '| --- | --- | --- | --- |',
    '| `micro` | 120ms |  | Hover, press |',
    '| `enter-curve` |  | `cubic-bezier(0.23, 1, 0.32, 1)` | Most changes |',
    '',
    '## Components'
  ].join('\n');
  assert.deepEqual(motionTable(markdown), {
    micro: { duration: '120ms' },
    'enter-curve': { timingFunction: 'cubic-bezier(0.23, 1, 0.32, 1)' }
  });
});

const DESIGN_MD = [
  '---',
  'name: PiFrame',
  'colors:',
  '  dark:',
  '    primary: "#5F9FC5"',
  'rounded:',
  '  sm: 6px',
  '---',
  '',
  '## Motion',
  '',
  '| Token | Duration | Timing function |',
  '| --- | --- | --- |',
  '| `micro` | 120ms |  |',
  ''
].join('\r\n');
const THEME = JSON.stringify({
  variant: 'dark',
  colors: { accent: '#5f9fc5' },
  radii: { sm: 6 },
  motion: { fast: 120 }
});
const checkInput = (overrides = {}) => ({
  design: DESIGN_MD,
  parseYaml: parse,
  themeFiles: [
    { file: DARK, text: THEME },
    { file: 'themes/theme.schema.json', text: '{"colors": {"accent": "#000000"}}' },
    { file: 'themes/README.md', text: '# Themes' }
  ],
  text: { file: TEXT, text: '' },
  motion: { file: MOTION, text: '  static const Duration micro = Duration(milliseconds: 120);' },
  scale: { file: SCALE, text: '' },
  ...overrides
});

test('the check reads the front matter and the Motion table (CRLF too), counting only the theme JSON files', () => {
  assert.deepEqual(checkDesignTokens(checkInput()), { ok: true, problems: [] });
});

test('DESIGN.md without front matter fails, saying what to add', () => {
  const result = checkDesignTokens(checkInput({ design: '# PiFrame\n' }));
  assert.equal(result.ok, false);
  assert.equal(result.problems.length, 1);
  assert.match(result.problems[0].message, /DESIGN\.md has no YAML front matter/);
  assert.match(result.problems[0].message, /To fix it/);
});

test('each mismatch says which file to edit', () => {
  const changed = { file: DARK, text: THEME.replace('#5f9fc5', '#ff0000').replace('"fast":120', '"fast":90') };
  const { problems } = checkDesignTokens(checkInput({ themeFiles: [changed] }));
  const messages = problems.map((p) => p.message);
  const color = messages.find((m) => m.startsWith('colors.dark.primary'));
  assert.match(color, /To fix it, set colors\.dark\.primary to #ff0000 in DESIGN\.md's front matter/);
  assert.match(color, /themes\/piframe-dark\.json/);
  const motion = messages.find((m) => m.startsWith('motion.micro.duration') && m.includes(DARK));
  assert.match(motion, /the Motion table of DESIGN\.md/);
});

test('a theme file that is not valid JSON fails, naming the file', () => {
  const { ok, problems } = checkDesignTokens(checkInput({ themeFiles: [{ file: DARK, text: '{' }] }));
  assert.equal(ok, false);
  assert.ok(problems.some((p) => p.message.includes(DARK) && /not valid JSON/.test(p.message)));
});
