import * as fs from 'node:fs';
import * as path from 'node:path';
import { withFileLock } from './lockfile.js';
import {
  readSettingsFile,
  writeTextAtomicallyWithBackup,
  writeJsonAtomicallyWithBackup,
  type SettingsWriterLockOptions,
} from './settingsWriter.js';

/**
 * Per-agent overrides written into the agent's own `.md` frontmatter.
 *
 * `@tintinweb/pi-subagents` reads a subagent's model and thinking level ONLY
 * from the agent file's frontmatter ("frontmatter is authoritative"); it ignores
 * `settings.json` `subagents.agentOverrides` (a nicobailon `pi-subagents` key)
 * and has no per-agent key in `subagents.json`. So for user-scope agents under
 * tintinweb, PiFrame edits the `model:` / `thinking:` line in place.
 *
 * Every other byte of the file is left as it was. The line PiFrame replaced is
 * recorded in `<piframeDir>/subagent-frontmatter-originals.json` the first time
 * a field is overridden, so a reset puts that exact line back (or removes the
 * line again if the field was absent). The file also gets a
 * `<file>.piframe-backup` copy before each write.
 */

export type AgentFileField = 'model' | 'thinking';

/** Original line per field; `null` means the field was absent from the frontmatter. */
export type AgentFileOriginals = Record<string, Partial<Record<AgentFileField, string | null>>>;

export const ORIGINALS_FILE = 'subagent-frontmatter-originals.json';

export function originalsKey(filePath: string): string {
  return path.resolve(filePath);
}

export function readAgentFileOriginals(piframeDir: string): AgentFileOriginals {
  try {
    const raw = readSettingsFile(path.join(piframeDir, ORIGINALS_FILE));
    const result: AgentFileOriginals = {};
    for (const [file, fields] of Object.entries(raw)) {
      if (!fields || typeof fields !== 'object' || Array.isArray(fields)) continue;
      const entry: Partial<Record<AgentFileField, string | null>> = {};
      for (const field of ['model', 'thinking'] as const) {
        if (field in fields) {
          const v = (fields as any)[field];
          if (v === null || typeof v === 'string') entry[field] = v;
        }
      }
      if (Object.keys(entry).length > 0) result[file] = entry;
    }
    return result;
  } catch {
    return {};
  }
}

interface FrontmatterLayout {
  bom: string;
  eol: string;
  /** All lines of the file (without line endings), BOM stripped. */
  lines: string[];
  /** Index of the closing `---` line, or -1 when there is no frontmatter block. */
  closeIdx: number;
  /** Whether the original content ended with a line ending. */
  trailingEol: boolean;
}

function layout(content: string): FrontmatterLayout {
  const bom = content.startsWith('﻿') ? '﻿' : '';
  const text = bom ? content.slice(1) : content;
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  const trailingEol = text.endsWith('\n');
  const lines = text.split(/\r?\n/);
  if (trailingEol) lines.pop();
  let closeIdx = -1;
  if (lines.length > 0 && lines[0].trimEnd() === '---') {
    for (let i = 1; i < lines.length; i++) {
      if (lines[i].trimEnd() === '---') {
        closeIdx = i;
        break;
      }
    }
  }
  return { bom, eol, lines, closeIdx, trailingEol };
}

function findKeyLine(l: FrontmatterLayout, key: string): number {
  if (l.closeIdx === -1) return -1;
  const re = new RegExp(`^${key}\\s*:`);
  for (let i = 1; i < l.closeIdx; i++) {
    if (re.test(l.lines[i])) return i;
  }
  return -1;
}

function join(l: FrontmatterLayout): string {
  return l.bom + l.lines.join(l.eol) + (l.trailingEol ? l.eol : '');
}

/** The exact top-level frontmatter line for `key`, or null when absent. */
export function getFrontmatterLine(content: string, key: string): string | null {
  const l = layout(content);
  const idx = findKeyLine(l, key);
  return idx === -1 ? null : l.lines[idx];
}

/**
 * Replace (or insert, or with `line === null` remove) the top-level frontmatter
 * line for `key`. Leaves every other line, the line endings, and the BOM as they were.
 */
export function setFrontmatterLine(content: string, key: string, line: string | null): string {
  const l = layout(content);
  const idx = findKeyLine(l, key);
  if (idx !== -1) {
    if (line === null) {
      l.lines.splice(idx, 1);
    } else {
      l.lines[idx] = line;
    }
    return join(l);
  }
  if (line === null) return content;
  if (l.closeIdx === -1) {
    // No frontmatter block: add one at the top.
    l.lines.unshift('---', line, '---');
    if (l.lines.length === 3) l.trailingEol = true;
    return join(l);
  }
  l.lines.splice(l.closeIdx, 0, line);
  return join(l);
}

export function formatFrontmatterLine(key: string, value: string): string {
  const plain = /^[A-Za-z0-9_][A-Za-z0-9_.\/@+:-]*$/.test(value) && !/:$/.test(value);
  return `${key}: ${plain ? value : JSON.stringify(value)}`;
}

export interface AgentFileChange {
  filePath: string;
  /** undefined = untouched, null = restore original, string = set. */
  model?: string | null;
  thinking?: string | null;
}

/**
 * Applies model/thinking overrides to agent files, recording/restoring the
 * original lines. Returns the set of files that were rewritten.
 */
export async function applyAgentFileChanges(
  piframeDir: string,
  changes: AgentFileChange[],
  lockOptions?: SettingsWriterLockOptions
): Promise<string[]> {
  if (changes.length === 0) return [];
  const originalsPath = path.join(piframeDir, ORIGINALS_FILE);
  const written: string[] = [];

  await withFileLock(
    originalsPath,
    async (originalsLock) => {
      const originals = readAgentFileOriginals(piframeDir);
      let originalsModified = false;

      for (const change of changes) {
        const key = originalsKey(change.filePath);
        await withFileLock(
          change.filePath,
          async (fileLock) => {
            if (!fs.existsSync(change.filePath)) {
              const err = new Error(`Agent file not found: ${change.filePath}`);
              throw Object.assign(err, { code: 'AGENTS_CONFIG_UNREADABLE' });
            }
            const before = fs.readFileSync(change.filePath, 'utf8');
            let content = before;
            const entry = { ...(originals[key] ?? {}) };

            for (const field of ['model', 'thinking'] as const) {
              const value = change[field];
              if (value === undefined) continue;
              if (value === null) {
                if (field in entry) {
                  content = setFrontmatterLine(content, field, entry[field] ?? null);
                  delete entry[field];
                }
              } else {
                if (!(field in entry)) {
                  entry[field] = getFrontmatterLine(content, field);
                }
                content = setFrontmatterLine(content, field, formatFrontmatterLine(field, value));
              }
            }

            if (Object.keys(entry).length > 0) {
              if (JSON.stringify(entry) !== JSON.stringify(originals[key])) {
                originals[key] = entry;
                originalsModified = true;
              }
            } else if (key in originals) {
              delete originals[key];
              originalsModified = true;
            }

            if (content !== before) {
              await writeTextAtomicallyWithBackup(change.filePath, content, {
                ...lockOptions,
                lockHandle: fileLock,
              });
              written.push(change.filePath);
            }
          },
          lockOptions
        );
      }

      if (originalsModified) {
        await writeJsonAtomicallyWithBackup(originalsPath, originals, {
          ...lockOptions,
          lockHandle: originalsLock,
        });
      }
    },
    lockOptions
  );

  return written;
}
