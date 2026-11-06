export interface ParsedFrontmatter {
  frontmatter: Record<string, any>;
  body: string;
}

function parseScalar(raw: string): any {
  const trimmed = raw.trim();
  if (trimmed === 'true' || trimmed === 'yes') return true;
  if (trimmed === 'false' || trimmed === 'no') return false;
  if (trimmed === 'null' || trimmed === '~') return null;

  // Quoted string
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }

  // Inline array: [a, b, c]
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    const inner = trimmed.slice(1, -1).trim();
    if (!inner) return [];
    return inner.split(',').map((s) => parseScalar(s.trim()));
  }

  // Integer / Number
  if (/^-?\d+$/.test(trimmed)) {
    const num = Number(trimmed);
    if (Number.isSafeInteger(num)) return num;
  }
  if (/^-?\d+\.\d+$/.test(trimmed)) {
    const num = Number(trimmed);
    if (Number.isFinite(num)) return num;
  }

  return trimmed;
}

/**
 * Minimal, safe YAML frontmatter parser for agent markdown definitions.
 * Evaluates NO code, supports flat keys, indented mappings (e.g. runner), and simple lists.
 */
export function parseFrontmatter(content: string): ParsedFrontmatter {
  const normalized = content.replace(/^\uFEFF/, '');
  const match = normalized.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);

  if (!match) {
    return { frontmatter: {}, body: normalized };
  }

  const rawYaml = match[1];
  const body = match[2];
  const lines = rawYaml.split(/\r?\n/);
  const result: Record<string, any> = {};

  let currentKey: string | null = null;
  let currentIndent = 0;

  for (const line of lines) {
    // Ignore comments and blank lines
    if (!line.trim() || line.trim().startsWith('#')) {
      continue;
    }

    const indentMatch = line.match(/^(\s*)/);
    const indent = indentMatch ? indentMatch[1].length : 0;

    if (indent === 0) {
      const colonIdx = line.indexOf(':');
      if (colonIdx === -1) continue;

      const key = line.slice(0, colonIdx).trim();
      const valStr = line.slice(colonIdx + 1).trim();

      currentKey = key;
      currentIndent = 0;

      if (valStr.length > 0) {
        result[key] = parseScalar(valStr);
      } else {
        // Will be populated by following indented lines
        result[key] = undefined;
      }
    } else if (currentKey) {
      const trimmedLine = line.trim();

      // List item
      if (trimmedLine.startsWith('- ')) {
        const itemVal = parseScalar(trimmedLine.slice(2));
        if (!Array.isArray(result[currentKey])) {
          result[currentKey] = [];
        }
        result[currentKey].push(itemVal);
      } else {
        // Nested mapping: key: value
        const colonIdx = trimmedLine.indexOf(':');
        if (colonIdx !== -1) {
          const subKey = trimmedLine.slice(0, colonIdx).trim();
          const subVal = parseScalar(trimmedLine.slice(colonIdx + 1));
          if (typeof result[currentKey] !== 'object' || result[currentKey] === null || Array.isArray(result[currentKey])) {
            result[currentKey] = {};
          }
          result[currentKey][subKey] = subVal;
        }
      }
    }
  }

  return { frontmatter: result, body };
}
