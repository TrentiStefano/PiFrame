import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { compactionThreshold, validateContextLimit, validateReservePercent, readContextPolicy, writeContextPolicy, deleteContextPolicy } from '../contextPolicy.js';
import { contextLimitExtension, physicalModel } from '../contextLimitExtension.js';

test('context policy: thresholds and untrusted bounds', () => {
  assert.equal(compactionThreshold(200000, 2.5), 195000);
  assert.equal(compactionThreshold(1000000, 5), 950000);
  assert.equal(validateContextLimit(200000, 200000), 200000);
  assert.equal(validateContextLimit(null, 200000), null);
  for (const value of [0, -1, 200001, 1.5, NaN, Infinity, '1000', undefined]) {
    assert.throws(() => validateContextLimit(value, 200000));
  }
  assert.throws(() => validateContextLimit(1000, 0));
  for (const value of [0, -1, 100, NaN, Infinity, '5', null]) assert.throws(() => validateReservePercent(value));
  assert.equal(validateReservePercent(5), 5);
});

test('context policy: persistence contains only preferences and survives reopening', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-context-test-'));
  const previous = process.env.PI_FRAME_HOME;
  process.env.PI_FRAME_HOME = home;
  try {
    assert.deepEqual(readContextPolicy('s_test'), { contextWindowOverride: null, compactionReservePercent: 2.5 });
    writeContextPolicy('s_test', { contextWindowOverride: 200000, compactionReservePercent: 5, secret: 'never persisted' } as any);
    assert.deepEqual(readContextPolicy('s_test'), { contextWindowOverride: 200000, compactionReservePercent: 5 });
    assert.equal(fs.readFileSync(path.join(home, 'context', 's_test.json'), 'utf8').includes('secret'), false);
    assert.throws(() => writeContextPolicy('../escape', { contextWindowOverride: null, compactionReservePercent: 5 }));
    deleteContextPolicy('s_test');
    assert.equal(readContextPolicy('s_test').contextWindowOverride, null);
  } finally {
    if (previous === undefined) delete process.env.PI_FRAME_HOME; else process.env.PI_FRAME_HOME = previous;
    fs.rmSync(home, { recursive: true, force: true });
  }
});

function runtime(settings: any = {}) {
  const handlers = new Map<string, any>();
  let command: any;
  const ctx = { model: { provider: 'test', id: 'model', contextWindow: 1000000 } as any };
  const pi = {
    getSettings: () => settings,
    registerCommand: (_: string, definition: any) => { command = definition; },
    on: (event: string, handler: any) => { handlers.set(event, handler); },
    setModel: async (model: any) => { ctx.model = model; await handlers.get('model_select')?.({}, ctx); return true; },
  };
  contextLimitExtension(pi);
  return { ctx, pi, handlers, setPolicy: async (limit: number | null, percent: number) => command.handler(JSON.stringify({ limit, percent }), ctx) };
}

test('runtime extension: starts with the displayed default reserve even without a custom limit', async () => {
  const r = runtime();
  await r.handlers.get('session_start')({}, r.ctx);
  assert.equal(r.ctx.model.contextWindow - 16384, 974999);
  assert.equal(r.ctx.model.piframeContextPolicy.percent, 2.5);
});

test('runtime extension: native compaction fires at selected tier, not full model window', async () => {
  const r = runtime();
  await r.setPolicy(200000, 2.5);
  const shouldCompact = (tokens: number) => tokens > r.ctx.model.contextWindow - 16384;
  assert.equal(shouldCompact(194999), false);
  assert.equal(shouldCompact(195000), true);
  assert.equal(physicalModel(r.ctx.model).contextWindow, 1000000);
  assert.equal(physicalModel(r.ctx.model).piframeContextPolicy, undefined);
  await r.setPolicy(1000000, 5);
  assert.equal(shouldCompact(949999), false);
  assert.equal(shouldCompact(950000), true);
});

test('runtime extension: respects Pi overrides and clamps on smaller model changes without recursion', async () => {
  const r = runtime({ compaction: { reserveTokens: 1000, modelOverrides: { 'test/model': { reserveTokens: 5000 } } } });
  await r.setPolicy(200000, 5);
  assert.equal(r.ctx.model.contextWindow - 5000, 189999);
  r.ctx.model = { provider: 'test', id: 'small', contextWindow: 64000 };
  await r.handlers.get('model_select')({}, r.ctx);
  assert.ok(r.ctx.model.contextWindow <= 64000);
  assert.equal(r.ctx.model.piframeOriginalContextWindow, 64000);
  await r.setPolicy(null, 5);
  assert.equal(r.ctx.model.contextWindow - 1000, 60799);
});

test('runtime extension: idle threshold compacts once, avoids failed-summary loops and honors disabled auto-compaction', async () => {
  const settings = { compaction: { enabled: true } };
  const r = runtime(settings);
  await r.setPolicy(200000, 2.5);
  let tokens = 194999;
  let attempts = 0;
  let callbacks: any;
  const ctx = { ...r.ctx, getContextUsage: () => ({ tokens }), compact: (options: any) => { attempts++; callbacks = options; } };
  const settle = () => r.handlers.get('agent_settled')({}, ctx);
  settle();
  assert.equal(attempts, 0);
  tokens = 195000;
  settle(); settle();
  assert.equal(attempts, 1);
  callbacks.onError(new Error('Summary failed'));
  settle();
  assert.equal(attempts, 1);
  tokens++;
  settle();
  assert.equal(attempts, 2);
  callbacks.onComplete();
  settings.compaction.enabled = false;
  tokens++;
  settle();
  assert.equal(attempts, 2);
});

test('runtime extension: emitted function is self-contained JavaScript', () => {
  assert.doesNotThrow(() => new Function(`return (${contextLimitExtension.toString()})`));
});
