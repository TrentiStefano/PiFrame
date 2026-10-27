import * as fs from 'node:fs';
import * as path from 'node:path';
import { getPiFrameBaseDir } from '../config/config.js';

export const DEFAULT_COMPACTION_RESERVE_PERCENT = 2.5;
export interface ContextPolicy {
  contextWindowOverride: number | null;
  compactionReservePercent: number;
}

export function validateContextLimit(value: unknown, modelMaximum: number): number | null {
  if (value === null) return null;
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value <= 0) {
    throw Object.assign(new Error('Il limite di contesto deve essere un numero intero positivo.'), { code: 'COMMAND_REJECTED' });
  }
  if (!Number.isSafeInteger(modelMaximum) || modelMaximum <= 0) {
    throw Object.assign(new Error('Dimensione massima del modello non disponibile.'), { code: 'COMMAND_REJECTED' });
  }
  if (value > modelMaximum) throw Object.assign(new Error(`Il contesto massimo del modello è ${modelMaximum} token.`), { code: 'COMMAND_REJECTED' });
  return value;
}

export function validateReservePercent(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value >= 100) {
    throw Object.assign(new Error('Il margine di compattazione deve essere maggiore di 0 e minore di 100%.'), { code: 'COMMAND_REJECTED' });
  }
  return value;
}

export function compactionThreshold(limit: number, percent: number): number {
  return Math.max(1, Math.floor(limit * (1 - percent / 100)));
}

function policyPath(sessionId: string): string {
  if (!/^[\w-]+$/.test(sessionId)) throw new Error('Invalid session id');
  return path.join(getPiFrameBaseDir(), 'context', `${sessionId}.json`);
}

export function readContextPolicy(sessionId: string): ContextPolicy {
  const defaults = { contextWindowOverride: null, compactionReservePercent: DEFAULT_COMPACTION_RESERVE_PERCENT };
  try {
    const parsed = JSON.parse(fs.readFileSync(policyPath(sessionId), 'utf8'));
    return {
      contextWindowOverride: validateContextLimit(parsed.contextWindowOverride, Number.MAX_SAFE_INTEGER),
      compactionReservePercent: validateReservePercent(parsed.compactionReservePercent),
    };
  } catch { return defaults; }
}

export function writeContextPolicy(sessionId: string, policy: ContextPolicy): void {
  const file = policyPath(sessionId);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify({
    contextWindowOverride: policy.contextWindowOverride,
    compactionReservePercent: policy.compactionReservePercent,
  }), { mode: 0o600 });
  fs.renameSync(temporary, file);
}

export function deleteContextPolicy(sessionId: string): void {
  fs.rmSync(policyPath(sessionId), { force: true });
}
