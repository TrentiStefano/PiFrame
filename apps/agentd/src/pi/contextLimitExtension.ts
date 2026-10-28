import * as fs from 'node:fs';
import * as path from 'node:path';
import { getPiFrameBaseDir } from '../config/config.js';
import type { StdioPiTransport } from './StdioPiTransport.js';
import type { ContextPolicy } from './contextPolicy.js';

/** Self-contained: emitted as a Pi extension without importing daemon dependencies. */
export function contextLimitExtension(pi: any): void {
  let policy: { limit: number | null; percent: number } | null = null;
  let applying = false;
  let compacting = false;
  let lastAttemptTokens: number | null = null;
  const apply = async (ctx: any) => {
    if (!policy || !ctx.model || applying) return;
    if (typeof pi.getSettings !== 'function') {
      throw new Error('Aggiorna Pi: questa versione non espone getSettings per i limiti di contesto.');
    }
    const model = ctx.model;
    const maximum = model.piframeOriginalContextWindow ?? model.contextWindow;
    const limit = Math.min(policy.limit ?? maximum, maximum);
    const settings = pi.getSettings();
    const compaction = settings.compaction ?? {};
    const overrides = compaction.modelOverrides?.[`${model.provider}/${model.id}`];
    const reserve = overrides?.reserveTokens ?? compaction.reserveTokens ?? 16384;
    if (!Number.isSafeInteger(reserve) || reserve < 0) throw new Error('Invalid Pi compaction.reserveTokens');
    const threshold = Math.max(1, Math.floor(limit * (1 - policy.percent / 100)));
    // Pi checks window - reserveTokens before the next assistant/tool continuation.
    // Shift only the in-memory window; never rewrite Pi settings or the model catalogue.
    // A larger native reserve can compact earlier, but never later than our threshold.
    const window = Math.max(1, Math.min(maximum, threshold + reserve - 1));
    if (model.contextWindow === window && model.piframeOriginalContextWindow === maximum &&
        model.piframeContextPolicy?.limit === policy.limit && model.piframeContextPolicy?.percent === policy.percent) return;
    applying = true;
    try {
      const ok = await pi.setModel({
        ...model, contextWindow: window, piframeOriginalContextWindow: maximum, piframeContextPolicy: policy,
        // RPC get_state serializes this live value; do not confuse cumulative session tokens with context usage.
        get piframeContextUsage() { return typeof ctx.getContextUsage === 'function' ? ctx.getContextUsage() : null; },
      });
      if (!ok) throw new Error('Impossibile applicare il limite al modello attivo.');
    } finally { applying = false; }
  };
  pi.registerCommand('piframe-reload', {
    description: 'PiFrame internal reload',
    handler: async (_args: string, ctx: any) => {
      // ctx.reload() is Pi's own resource reload (extensions, skills, prompts, context files).
      if (typeof ctx?.reload !== 'function') throw new Error('Aggiorna Pi: ricaricamento non disponibile in questa versione.');
      await ctx.reload();
    },
  });
  pi.registerCommand('piframe-context-policy', {
    description: 'PiFrame internal context policy',
    handler: async (args: string, ctx: any) => {
      const next = JSON.parse(args);
      if ((next.limit !== null && (!Number.isSafeInteger(next.limit) || next.limit <= 0)) ||
          typeof next.percent !== 'number' || !Number.isFinite(next.percent) || next.percent <= 0 || next.percent >= 100) {
        throw new Error('Invalid PiFrame context policy');
      }
      const previous = policy;
      policy = next;
      try { await apply(ctx); lastAttemptTokens = null; } catch (error) { policy = previous; throw error; }
    },
  });
  pi.on('session_start', async (_event: unknown, ctx: any) => {
    compacting = false;
    lastAttemptTokens = null;
    // Older Pi versions keep their native defaults until a policy is explicitly requested.
    if (typeof pi.getSettings !== 'function') { policy = null; return; }
    policy = { limit: null, percent: 2.5 };
    await apply(ctx);
  });
  pi.on('agent_settled', (_event: unknown, ctx: any) => {
    if (!policy || compacting || pi.getSettings().compaction?.enabled === false) return;
    const usage = ctx.getContextUsage();
    const tokens = usage?.tokens;
    if (typeof tokens !== 'number' || !ctx.model) return;
    const maximum = ctx.model.piframeOriginalContextWindow ?? ctx.model.contextWindow;
    const limit = Math.min(policy.limit ?? maximum, maximum);
    const threshold = Math.max(1, Math.floor(limit * (1 - policy.percent / 100)));
    if (tokens < threshold) { lastAttemptTokens = null; return; }
    // No tight retries when a summary fails or cannot shrink the retained context.
    if (lastAttemptTokens !== null && tokens <= lastAttemptTokens) return;
    lastAttemptTokens = tokens;
    compacting = true;
    try {
      ctx.compact({
        customInstructions: `Keep the summarized context below ${threshold} tokens while preserving decisions and pending work.`,
        onComplete: () => { compacting = false; },
        onError: () => { compacting = false; },
      });
    } catch (error) { compacting = false; throw error; }
  });
  pi.on('model_select', async (_event: unknown, ctx: any) => { await apply(ctx); });
  pi.on('before_agent_start', async (_event: unknown, ctx: any) => { await apply(ctx); });
}

export function ensureContextLimitExtension(): string {
  const directory = path.join(getPiFrameBaseDir(), 'runtime');
  fs.mkdirSync(directory, { recursive: true });
  const file = path.join(directory, 'context-limit.mjs');
  const source = `export default ${contextLimitExtension.toString()}\n`;
  if (!fs.existsSync(file) || fs.readFileSync(file, 'utf8') !== source) {
    const temporary = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, source, { mode: 0o600 });
    fs.renameSync(temporary, file);
  }
  return file;
}

export async function applyContextPolicy(worker: StdioPiTransport, policy: ContextPolicy): Promise<any> {
  const configuration = { limit: policy.contextWindowOverride, percent: policy.compactionReservePercent };
  await worker.send({ command: 'prompt', arguments: { message: `/piframe-context-policy ${JSON.stringify(configuration)}` } });
  const state = (await worker.send({ command: 'get_state' })).data;
  const applied = state?.model?.piframeContextPolicy;
  if (applied?.limit !== configuration.limit || applied?.percent !== configuration.percent) {
    throw new Error('Pi non ha applicato il limite di contesto. Aggiorna Pi e riavvia il worker.');
  }
  return physicalModel(state.model);
}

export function physicalModel(model: any): any {
  if (!model || model.piframeOriginalContextWindow === undefined) return model;
  const { piframeOriginalContextWindow, piframeContextPolicy, piframeContextUsage, ...rest } = model;
  return { ...rest, contextWindow: piframeOriginalContextWindow };
}
