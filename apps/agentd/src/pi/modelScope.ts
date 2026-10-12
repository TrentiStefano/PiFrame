import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

export function readEnabledModelPatterns(agentDir = process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), '.pi', 'agent')): string[] {
  try {
    const settings = JSON.parse(fs.readFileSync(path.join(agentDir, 'settings.json'), 'utf8'));
    return Array.isArray(settings.enabledModels)
      ? settings.enabledModels.filter((pattern: unknown): pattern is string => typeof pattern === 'string' && pattern.trim().length > 0)
      : [];
  } catch {
    return [];
  }
}

function globRegex(pattern: string): RegExp {
  let source = '^';
  for (let index = 0; index < pattern.length; index++) {
    const character = pattern[index];
    if (character === '*') source += '.*';
    else if (character === '?') source += '.';
    else if (character === '[') {
      const end = pattern.indexOf(']', index + 1);
      const group = end > index ? pattern.slice(index + 1, end) : '';
      if (end < 0 || !/^[\w-]+$/.test(group)) source += '\\[';
      else {
        source += `[${group}]`;
        index = end;
      }
    } else source += character.replace(/[|\\{}()[\]^$+?.]/g, '\\$&');
  }
  return new RegExp(`${source}$`, 'i');
}

function resolvePattern(pattern: string, models: Array<Record<string, any>>): Array<Record<string, any>> {
  const reference = pattern.trim().toLowerCase();
  const exact = models.filter((model) =>
    `${model.provider}/${model.id}`.toLowerCase() === reference || String(model.id).toLowerCase() === reference,
  );
  if (exact.length === 1) return exact;
  if (exact.length > 1) return [];

  const colon = pattern.lastIndexOf(':');
  const suffix = colon > pattern.indexOf('/') ? pattern.slice(colon + 1).toLowerCase() : '';
  if (['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'].includes(suffix)) {
    return resolvePattern(pattern.slice(0, colon), models);
  }

  if (/[*?[]/.test(pattern)) {
    const matcher = globRegex(pattern);
    return models.filter((model) => matcher.test(`${model.provider}/${model.id}`) || matcher.test(String(model.id)));
  }

  const partial = pattern.toLowerCase();
  const matches = models.filter((model) =>
    String(model.id).toLowerCase().includes(partial) || String(model.name ?? '').toLowerCase().includes(partial),
  );
  if (matches.length === 0) return [];
  const aliases = matches.filter((model) => !/-\d{8}$/.test(String(model.id)));
  const preferred = aliases.length > 0 ? aliases : matches;
  return [[...preferred].sort((a, b) => String(b.id).localeCompare(String(a.id)))[0]];
}

/** Match Pi's enabledModels scope against models already filtered by Pi authentication. */
export function filterModelsByEnabledPatterns(
  models: Array<Record<string, any>>,
  patterns: string[],
): Array<Record<string, any>> {
  if (patterns.length === 0) return models;
  const selected = new Map<string, Record<string, any>>();
  for (const pattern of patterns) {
    for (const model of resolvePattern(pattern.trim(), models)) {
      selected.set(`${model.provider}\0${model.id}`, model);
    }
  }
  return models.filter((model) => selected.has(`${model.provider}\0${model.id}`));
}
