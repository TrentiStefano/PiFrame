import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { getPiFrameBaseDir } from '../../config/config.js';

export function readSubagentContextLimits(baseDir = getPiFrameBaseDir()): Record<string, number> {
  try {
    const file = path.join(baseDir, 'subagent-context.json');
    if (!fs.existsSync(file)) return {};
    const content = fs.readFileSync(file, 'utf8');
    const parsed = JSON.parse(content);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      const result: Record<string, number> = {};
      for (const [key, val] of Object.entries(parsed)) {
        if (typeof val === 'number' && Number.isSafeInteger(val) && val > 0) {
          result[key] = val;
        }
      }
      return result;
    }
    return {};
  } catch {
    return {};
  }
}

/**
 * Extension handler logic for subagent context limit.
 * Reads agent name from system prompt <active_agent name="..."> tag.
 * If model has tiers and limit < contextWindow, calls pi.setModel.
 */
export function subagentContextLimitExtension(pi: any): void {
  const getContextLimits = (): Record<string, number> => {
    try {
      const baseDir = process.env.PI_FRAME_HOME || path.join(os.homedir(), '.piframe');
      const file = path.join(baseDir, 'subagent-context.json');
      if (!fs.existsSync(file)) return {};
      return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch {
      return {};
    }
  };

  const apply = async (event: any, ctx: any) => {
    if (!ctx?.model) return;
    const prompt =
      event?.systemPrompt ||
      ctx?.systemPrompt ||
      (typeof ctx?.getSystemPrompt === 'function' ? ctx.getSystemPrompt() : '');
    if (typeof prompt !== 'string') return;

    const match = prompt.match(/<active_agent\s+name=["']([^"']+)["']/);
    if (!match) return;
    const agentName = match[1];

    const limits = getContextLimits();
    const limit = limits[agentName];
    if (
      typeof limit === 'number' &&
      Array.isArray(ctx.model.cost?.tiers) &&
      ctx.model.cost.tiers.length > 0 &&
      limit < ctx.model.contextWindow
    ) {
      if (typeof pi.setModel === 'function') {
        await pi.setModel({
          ...ctx.model,
          contextWindow: limit,
        });
      }
    }
  };

  pi.on('session_start', async (event: any, ctx: any) => {
    await apply(event, ctx);
  });

  pi.on('before_agent_start', async (event: any, ctx: any) => {
    await apply(event, ctx);
  });
}

export function generateSubagentContextLimitSource(): string {
  return `import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';

export default function subagentContextLimitExtension(pi) {
  const getContextLimits = () => {
    try {
      const baseDir = process.env.PI_FRAME_HOME || path.join(os.homedir(), '.piframe');
      const file = path.join(baseDir, 'subagent-context.json');
      if (!fs.existsSync(file)) return {};
      return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch {
      return {};
    }
  };

  const apply = async (event, ctx) => {
    if (!ctx?.model) return;
    const prompt =
      event?.systemPrompt ||
      ctx?.systemPrompt ||
      (typeof ctx?.getSystemPrompt === 'function' ? ctx.getSystemPrompt() : '');
    if (typeof prompt !== 'string') return;

    const match = prompt.match(/<active_agent\\s+name=["']([^"']+)["']/);
    if (!match) return;
    const agentName = match[1];

    const limits = getContextLimits();
    const limit = limits[agentName];
    if (
      typeof limit === 'number' &&
      Array.isArray(ctx.model.cost?.tiers) &&
      ctx.model.cost.tiers.length > 0 &&
      limit < ctx.model.contextWindow
    ) {
      if (typeof pi.setModel === 'function') {
        await pi.setModel({
          ...ctx.model,
          contextWindow: limit,
        });
      }
    }
  };

  pi.on('session_start', async (event, ctx) => {
    await apply(event, ctx);
  });

  pi.on('before_agent_start', async (event, ctx) => {
    await apply(event, ctx);
  });
}
`;
}

export function ensureSubagentContextLimitExtension(baseDir = getPiFrameBaseDir()): string {
  const directory = path.join(baseDir, 'runtime');
  fs.mkdirSync(directory, { recursive: true });
  const file = path.join(directory, 'subagent-context-limit.mjs');
  const source = generateSubagentContextLimitSource();
  if (!fs.existsSync(file) || fs.readFileSync(file, 'utf8') !== source) {
    const temporary = `${file}.${process.pid}.${Date.now()}.tmp`;
    fs.writeFileSync(temporary, source, { encoding: 'utf8', mode: 0o600 });
    fs.renameSync(temporary, file);
  }
  return file;
}

export interface EnsureSubagentContextLimitOptions {
  agentDir?: string;
  piframeDir?: string;
}

/**
 * Checks if settings.json in agentDir references PiFrame's subagent context extension path
 * in any subagents.agentOverrides.*.subagentOnlyExtensions.
 * If so, (re)generates subagent-context-limit.mjs in piframeDir/runtime if missing or outdated.
 * This is a read-only check of settings.json: settings.json is NEVER modified at startup.
 * Returns the path to subagent-context-limit.mjs if generated/ensured, or null if not referenced.
 */
export function ensureSubagentContextLimitExtensionIfReferenced(
  options: EnsureSubagentContextLimitOptions = {}
): string | null {
  try {
    const agentDir =
      options.agentDir ||
      process.env.PI_CODING_AGENT_DIR ||
      path.join(os.homedir(), '.pi', 'agent');
    const piframeDir = options.piframeDir || getPiFrameBaseDir();

    const settingsPath = path.join(agentDir, 'settings.json');
    if (!fs.existsSync(settingsPath)) {
      return null;
    }

    let content: string;
    try {
      content = fs.readFileSync(settingsPath, 'utf8');
    } catch {
      return null;
    }

    if (content.charCodeAt(0) === 0xFEFF) {
      content = content.slice(1);
    }

    let settings: any;
    try {
      settings = JSON.parse(content);
    } catch {
      return null;
    }

    if (!settings || typeof settings !== 'object' || Array.isArray(settings)) {
      return null;
    }

    const agentOverrides = settings.subagents?.agentOverrides;
    if (!agentOverrides || typeof agentOverrides !== 'object' || Array.isArray(agentOverrides)) {
      return null;
    }

    const targetFile = path.resolve(piframeDir, 'runtime', 'subagent-context-limit.mjs');
    const targetNorm = path.normalize(targetFile).toLowerCase();

    const matchesExtension = (extPath: unknown): boolean => {
      if (typeof extPath !== 'string') return false;
      const resolvedNorm = path.normalize(path.resolve(extPath)).toLowerCase();
      if (resolvedNorm === targetNorm) return true;
      const normalized = path.normalize(extPath).toLowerCase();
      if (normalized === targetNorm) return true;
      if (path.basename(extPath) === 'subagent-context-limit.mjs') {
        const unified = normalized.replace(/\\/g, '/');
        if (unified.includes('.piframe/runtime') || unified.includes('.piframe')) {
          return true;
        }
      }
      return false;
    };

    let referenced = false;
    for (const override of Object.values(agentOverrides)) {
      if (
        override &&
        typeof override === 'object' &&
        Array.isArray((override as any).subagentOnlyExtensions)
      ) {
        if ((override as any).subagentOnlyExtensions.some(matchesExtension)) {
          referenced = true;
          break;
        }
      }
    }

    if (referenced) {
      return ensureSubagentContextLimitExtension(piframeDir);
    }

    return null;
  } catch {
    return null;
  }
}

