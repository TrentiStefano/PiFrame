import * as fs from 'node:fs';
import * as path from 'node:path';

export const SIDE_GUARDRAIL_PREAMBLE = `# Side Assistant Guardrails
You are a read-only side assistant for this workspace session.
Your role is to answer the user's side questions using the conversation snapshot below and by inspecting files in the workspace.
You may only read files (using tools: read, grep, find, ls).
You must never attempt to modify files, run bash commands, or alter the session state.

# Conversation Snapshot
`;

export const DEFAULT_MAX_SNAPSHOT_CHARS = 120_000;
export const MAX_INDIVIDUAL_TOOL_OUTPUT_CHARS = 500;

export interface RenderSnapshotOptions {
  messages: Array<any>;
  preamble?: string;
  maxChars?: number;
}

function extractText(content: any): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .filter((block) => block && (block.type === 'text' || typeof block.text === 'string'))
      .map((block) => block.text || '')
      .join('\n');
  }
  return '';
}

function extractToolSummaries(msg: any): string[] {
  const summaries: string[] = [];
  const calls: any[] = [];

  if (Array.isArray(msg.toolCalls)) {
    calls.push(...msg.toolCalls);
  }
  if (Array.isArray(msg.content)) {
    for (const b of msg.content) {
      if (b && (b.type === 'toolCall' || b.type === 'tool_call')) {
        calls.push(b);
      }
    }
  }

  for (const call of calls) {
    const name = call.name || call.toolName || 'tool';
    const args = call.arguments || {};
    let target = '';
    if (typeof args === 'string') {
      target = args;
    } else if (typeof args === 'object' && args !== null) {
      target = args.pattern || args.path || args.file || args.command || Object.values(args)[0] || '';
      if (typeof target === 'object') {
        try {
          target = JSON.stringify(target);
        } catch {
          target = '';
        }
      }
    }
    summaries.push(`tool(${name}): ${target}`);
  }

  return summaries;
}

export function renderMessageBlock(entry: any): string {
  const msg = entry.message || entry;
  const role = msg.role || 'unknown';

  if (role === 'user') {
    const text = extractText(msg.content);
    return `### User\n${text}\n\n`;
  }

  if (role === 'assistant') {
    const text = extractText(msg.content);
    const toolSummaries = extractToolSummaries(msg);
    const parts: string[] = [];
    if (text.trim().length > 0) {
      parts.push(text);
    }
    if (toolSummaries.length > 0) {
      parts.push(toolSummaries.join('\n'));
    }
    return `### Assistant\n${parts.join('\n')}\n\n`;
  }

  if (role === 'toolResult' || role === 'tool_result') {
    const name = msg.toolName || msg.name || 'tool';
    const rawOutput = extractText(msg.content);
    let output = rawOutput;
    if (output.length > MAX_INDIVIDUAL_TOOL_OUTPUT_CHARS) {
      output = output.slice(0, MAX_INDIVIDUAL_TOOL_OUTPUT_CHARS) + '... [output truncated]';
    }
    return `tool_result(${name}): ${output}\n\n`;
  }

  // Fallback for other roles (e.g. bash execution, etc.)
  const text = extractText(msg.content);
  if (text.trim().length > 0) {
    return `### ${role}\n${text}\n\n`;
  }

  return '';
}

export function renderConversationSnapshot(opts: RenderSnapshotOptions): string {
  const preamble = opts.preamble ?? SIDE_GUARDRAIL_PREAMBLE;
  const maxChars = opts.maxChars ?? DEFAULT_MAX_SNAPSHOT_CHARS;
  const messages = opts.messages || [];

  const renderedBlocks: string[] = [];
  for (const msg of messages) {
    const block = renderMessageBlock(msg);
    if (block) {
      renderedBlocks.push(block);
    }
  }

  // Calculate total length of blocks
  let totalChars = renderedBlocks.reduce((acc, b) => acc + b.length, 0);

  if (totalChars <= maxChars) {
    return `${preamble}${renderedBlocks.join('')}`;
  }

  // If exceeds maxChars, keep the most recent entries and note truncation
  const keptBlocks: string[] = [];
  let currentChars = 0;

  for (let i = renderedBlocks.length - 1; i >= 0; i--) {
    const block = renderedBlocks[i];
    if (currentChars + block.length <= maxChars) {
      keptBlocks.unshift(block);
      currentChars += block.length;
    } else {
      // If we couldn't even fit one block, truncate the single block to maxChars
      if (keptBlocks.length === 0) {
        keptBlocks.push(block.slice(block.length - maxChars));
      }
      break;
    }
  }

  const truncationNotice = `[Snapshot truncated: displaying the most recent conversation entries within ${maxChars.toLocaleString()} characters limit]\n\n`;
  return `${preamble}${truncationNotice}${keptBlocks.join('')}`;
}

export function writeSideContextFile(baseDir: string, sideId: string, content: string): string {
  const dir = path.join(baseDir, 'runtime', 'side', sideId);
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const filePath = path.join(dir, 'context.md');
  fs.writeFileSync(filePath, content, { encoding: 'utf8', mode: 0o600 });
  return filePath;
}

export function cleanupSideContextDir(baseDir: string, sideId: string): void {
  const dir = path.join(baseDir, 'runtime', 'side', sideId);
  try {
    if (fs.existsSync(dir)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  } catch {
    // Ignore cleanup errors
  }
}

export function cleanStaleSideDirs(baseDir: string): void {
  const sideRuntimeDir = path.join(baseDir, 'runtime', 'side');
  try {
    if (fs.existsSync(sideRuntimeDir)) {
      const entries = fs.readdirSync(sideRuntimeDir, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.isDirectory()) {
          const entryPath = path.join(sideRuntimeDir, entry.name);
          fs.rmSync(entryPath, { recursive: true, force: true });
        }
      }
    }
  } catch (err) {
    console.warn('[SideConversationManager] Failed to clean stale side directories:', err);
  }
}

