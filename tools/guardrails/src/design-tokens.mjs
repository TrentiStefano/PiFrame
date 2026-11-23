/**
 * Design token match: DESIGN.md's front-matter tokens must equal the values the theme files and the theme package
 * ship (themes/*.json and packages/pi_frame_theme are the source of truth).
 *
 * Pure: no I/O. tools/scripts/check-design-tokens.mjs reads the files and calls checkDesignTokens.
 */
import { normalizeLineEndings } from './markdown.mjs';

/** @typedef {{ file: string, tokens: Record<string, string> }} TokenSource a file and the token paths it defines */
/** @typedef {{ token?: string, design?: string, theme?: string, file?: string, message: string }} Problem */
/** @typedef {{ file: string, text: string }} TextFile */

/** The design system file, relative to the repository root. */
export const DESIGN_PATH = 'DESIGN.md';
/** The theme package sources the check reads, relative to the repository root. */
export const THEME_PACKAGE_FILES = {
  text: 'packages/pi_frame_theme/lib/src/theme_text.dart',
  motion: 'packages/pi_frame_theme/lib/src/theme_motion.dart',
  scale: 'packages/pi_frame_theme/lib/src/theme_scale.dart'
};

/** A theme file: a JSON file directly in themes/, the JSON Schema excluded. */
export const isThemeFile = (path) => /^themes\/[^/]+\.json$/.test(path) && !path.endsWith('.schema.json');

/** YAML front matter: a block between two `---` lines at the very top. */
const FRONT_MATTER = /^---\n([\s\S]*?)\n---(?:\n|$)/;

/**
 * The whole check: DESIGN.md's front matter plus its Motion table against the theme files and the theme package.
 *
 * @param {object} input
 * @param {string} input.design the DESIGN.md text
 * @param {(yaml: string) => object} input.parseYaml a YAML parser (the `yaml` package's `parse`)
 * @param {TextFile[]} input.themeFiles the files in themes/; only the theme JSON files (isThemeFile) are compared
 * @param {TextFile} input.text theme_text.dart
 * @param {TextFile} input.motion theme_motion.dart
 * @param {TextFile} input.scale theme_scale.dart
 * @returns {{ ok: boolean, problems: Problem[] }}
 */
export function checkDesignTokens({ design, parseYaml, themeFiles, text, motion, scale }) {
  const markdown = normalizeLineEndings(design);
  const frontMatter = markdown.match(FRONT_MATTER);
  if (!frontMatter) {
    return failed(
      `${DESIGN_PATH} has no YAML front matter. To fix it, put the design tokens in a block between two "---" ` +
        `lines at the very top of ${DESIGN_PATH}.`
    );
  }
  let tokens;
  try {
    tokens = parseYaml(frontMatter[1]) ?? {};
  } catch (error) {
    return failed(`${DESIGN_PATH}'s front matter is not valid YAML (${error.message}). To fix it, correct the YAML.`);
  }
  // Motion is a table in the Motion section until the pinned linter accepts the spec's motion group (see motionTable).
  const designTokens = { ...tokens, motion: motionTable(markdown) };

  const themes = [];
  const problems = [];
  for (const { file, text: json } of themeFiles.filter(({ file }) => isThemeFile(file))) {
    try {
      themes.push({ file, theme: JSON.parse(json) });
    } catch (error) {
      problems.push({ file, message: `${file} is not valid JSON (${error.message}). To fix it, correct ${file}.` });
    }
  }
  if (problems.length > 0) return { ok: false, problems };
  return designTokenMatch({
    design: designTokens,
    sources: themeTokenSources({ themes: themes.sort((a, b) => a.file.localeCompare(b.file)), text, motion, scale })
  });
}

const failed = (message) => ({ ok: false, problems: [{ message }] });

/** Where in DESIGN.md a token is written: motion tokens in the Motion table, the rest in the front matter. */
const designPlace = (token) =>
  token.startsWith('motion.') ? `the Motion table of ${DESIGN_PATH}` : `${DESIGN_PATH}'s front matter`;

/**
 * @param {object} input
 * @param {object} input.design the DESIGN.md tokens: the parsed front matter, plus `motion` from the Motion table
 * @param {TokenSource[]} input.sources the token values each theme file defines
 * @returns {{ ok: boolean, problems: Problem[] }} each message names the token, both values and the file to edit
 */
export function designTokenMatch({ design, sources }) {
  const designTokens = flatten(design);
  const problems = [];
  const defined = new Set();
  for (const { file, tokens } of sources) {
    for (const [token, value] of Object.entries(tokens)) {
      defined.add(token);
      const theme = normalize(value);
      const expected = designTokens.get(token);
      if (expected === undefined) {
        problems.push({
          token,
          theme,
          file,
          message:
            `${token}: ${file} has ${theme}, ${DESIGN_PATH} does not define it. To fix it, add ${token} = ${theme} ` +
            `to ${designPlace(token)}.`
        });
      } else if (expected !== theme) {
        problems.push({
          token,
          design: expected,
          theme,
          file,
          message:
            `${token}: ${DESIGN_PATH} has ${expected}, ${file} has ${theme}. To fix it, set ${token} to ${theme} in ` +
            `${designPlace(token)} (${file} is the source of truth; change it instead only if the theme itself ` +
            'should change).'
        });
      }
    }
  }
  const files = sources.map(({ file }) => file).join(', ');
  for (const [token, expected] of designTokens) {
    if (defined.has(token)) continue;
    problems.push({
      token,
      design: expected,
      message:
        `${token}: ${DESIGN_PATH} has ${expected}, no theme file defines it (${files}). To fix it, remove ${token} ` +
        `from ${designPlace(token)}, or add it to the theme file or theme package constant that should ship it.`
    });
  }
  return { ok: problems.length === 0, problems };
}

/** The token groups the theme defines; `components` only references them and is not compared. */
const COMPARED_GROUPS = ['colors', 'typography', 'rounded', 'spacing', 'motion'];

/** DESIGN.md's compared token groups as dot paths to normalized leaf values. */
function flatten(design) {
  const out = new Map();
  const walk = (node, path) => {
    if (node !== null && typeof node === 'object') {
      for (const [key, child] of Object.entries(node)) walk(child, `${path}.${key}`);
    } else if (!REFERENCE.test(String(node))) {
      out.set(path, normalize(node));
    }
  };
  for (const group of COMPARED_GROUPS) if (design?.[group] !== undefined) walk(design[group], group);
  return out;
}

/** One spelling per value: lower case, no spaces, `6.0px` → `6px`. */
function normalize(value) {
  return String(value)
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '')
    .replace(/(\d+(?:\.\d+)?)(px|ms)$/, (_, n, unit) => `${Number(n)}${unit}`);
}

/** Theme color keys whose DESIGN.md name is not their kebab-case spelling: the accent is the primary color. */
const COLOR_NAMES = { accent: 'primary', accentContrast: 'on-primary' };
/** The theme's motion keys and the theme package constant each one overrides (FrameTokens' defaults). */
const THEME_MOTION = { fast: 'micro', normal: 'panel' };
/** The theme's font families as used by FrameText's `_style(<family>, ...)` calls. */
const FAMILY = { ui: 'uiFontFamily', code: 'monoFontFamily' };

const kebab = (name) => name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);
const px = (n) => `${Number(n)}px`;
const ms = (n) => `${Number(n)}ms`;

/**
 * The token values the theme files and the theme package define, as DESIGN.md token paths, one source per file.
 *
 * @param {object} input
 * @param {{ file: string, theme: object }[]} input.themes parsed themes/*.json files
 * @param {{ file: string, text: string }} input.text theme_text.dart (FrameText roles)
 * @param {{ file: string, text: string }} input.motion theme_motion.dart (FrameMotionTokens)
 * @param {{ file: string, text: string }} input.scale theme_scale.dart (FrameSpace)
 * @returns {TokenSource[]}
 */
export function themeTokenSources({ themes, text, motion, scale }) {
  const roles = textRoles(text.text);
  const sources = themes.map(({ file, theme }) => {
    const tokens = {};
    const mode = theme.variant;
    for (const [key, value] of Object.entries(theme.colors ?? {})) {
      tokens[`colors.${mode}.${COLOR_NAMES[key] ?? kebab(key)}`] = value;
    }
    for (const [key, value] of Object.entries(theme.syntax ?? {}))
      tokens[`colors.${mode}.syntax-${kebab(key)}`] = value;
    for (const [key, value] of Object.entries(theme.radii ?? {})) tokens[`rounded.${key}`] = px(value);
    for (const [key, value] of Object.entries(theme.motion ?? {})) {
      if (THEME_MOTION[key]) tokens[`motion.${THEME_MOTION[key]}.duration`] = ms(value);
    }
    const families = theme.typography ?? {};
    if (families.headingFontFamily) tokens['typography.brand-heading.fontFamily'] = families.headingFontFamily;
    for (const { role, family } of roles) tokens[`typography.${role}.fontFamily`] = families[FAMILY[family]];
    return { file, tokens };
  });

  const textTokens = {};
  for (const { role, size, lineHeight, weight } of roles) {
    textTokens[`typography.${role}.fontSize`] = px(size);
    textTokens[`typography.${role}.lineHeight`] = px(lineHeight);
    textTokens[`typography.${role}.fontWeight`] = weight;
  }

  const motionTokens = {};
  for (const [, name, value] of motion.text.matchAll(
    /static const Duration (\w+) = Duration(?:\.zero|\(milliseconds: (\d+)\));/g
  )) {
    motionTokens[`motion.${kebab(name)}.duration`] = ms(value ?? 0);
  }
  for (const [, name, args] of motion.text.matchAll(/static const Cubic (\w+) = Cubic\(([^)]*)\);/g)) {
    motionTokens[`motion.${kebab(name)}.timingFunction`] = `cubic-bezier(${args
      .split(',')
      .map((a) => a.trim())
      .join(', ')})`;
  }

  const spaceClass = scale.text.match(/class FrameSpace \{([\s\S]*?)\n\}/)?.[1] ?? '';
  const spaceTokens = {};
  for (const [, name, value] of spaceClass.matchAll(/static const double (\w+) = ([\d.]+);/g)) {
    spaceTokens[`spacing.${name}`] = px(value);
  }

  return [
    ...sources,
    { file: text.file, tokens: textTokens },
    { file: motion.file, tokens: motionTokens },
    { file: scale.file, tokens: spaceTokens }
  ];
}

/** FrameText.fromTokens' `<role>: _style(<family>, <size>, <lineHeight>[, weight: FontWeight.w<n>])` lines. */
function textRoles(text) {
  const out = [];
  const line = /(\w+): _style\((ui|code), ([\d.]+), ([\d.]+)(?:, weight: FontWeight\.w(\d+))?\)/g;
  for (const [, role, family, size, lineHeight, weight = '400'] of text.matchAll(line)) {
    out.push({ role: kebab(role), family, size, lineHeight, weight });
  }
  return out;
}

const REFERENCE = /^\{[\w.-]+\}$/;

/**
 * The motion tokens in DESIGN.md's `## Motion` section table (`| Token | Duration | Timing function | ... |`). They
 * are a table, not front matter, because the pinned linter (@google/design.md 0.4.0) warns on the spec's `motion`
 * group; move them to the front matter once it accepts that group.
 *
 * @param {string} markdown the whole DESIGN.md
 * @returns {Record<string, { duration?: string, timingFunction?: string }>}
 */
export function motionTable(markdown) {
  const section = normalizeLineEndings(markdown).match(/^## Motion[^\n]*\n([\s\S]*?)(?=^## |(?![\s\S]))/m)?.[1] ?? '';
  const rows = section.split('\n').filter((line) => line.trim().startsWith('|'));
  const cells = (line) =>
    line
      .trim()
      .replace(/^\||\|$/g, '')
      .split('|')
      .map((c) => c.trim().replace(/^`|`$/g, ''));
  const [header, , ...body] = rows;
  if (!header) return {};
  const columns = cells(header).map((c) => c.toLowerCase());
  const at = (row, name) => row[columns.indexOf(name)] ?? '';
  const out = {};
  for (const line of body) {
    const row = cells(line);
    const token = {};
    if (at(row, 'duration')) token.duration = at(row, 'duration');
    if (at(row, 'timing function')) token.timingFunction = at(row, 'timing function');
    out[at(row, 'token')] = token;
  }
  return out;
}
