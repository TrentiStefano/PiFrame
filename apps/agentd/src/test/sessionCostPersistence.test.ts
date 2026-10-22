import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { SessionIndex } from '../sessions/SessionIndex.js';

test('SessionIndex: extractSessionMetadata correctly extracts usage, model, thinking, and cost', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-cost-test-'));
  const sessionFile = path.join(tmpDir, 'test-session.jsonl');

  t.after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  const lines = [
    JSON.stringify({ type: 'session', id: 'session-1', cwd: '/test' }),
    JSON.stringify({ type: 'model_change', modelId: 'claude-3-5-sonnet' }),
    JSON.stringify({ type: 'thinking_change', thinkingLevel: 'high' }),
    JSON.stringify({
      type: 'message',
      role: 'assistant',
      content: 'Thinking and acting...',
      usage: {
        cost: 0.015,
        tokens: { total: 4000, input: 3000, output: 1000 },
      },
    }),
    JSON.stringify({
      type: 'message',
      role: 'assistant',
      content: 'Finished task.',
      usage: {
        cost: { total: 0.025 },
        tokens: { total: 6500, input: 5000, output: 1500 },
      },
    }),
  ];

  fs.writeFileSync(sessionFile, lines.join('\n'), 'utf8');

  const index = new SessionIndex();
  const meta = index.extractSessionMetadata(sessionFile);

  assert.strictEqual(meta.model, 'claude-3-5-sonnet');
  assert.strictEqual(meta.thinkingLevel, 'high');
  assert.ok(meta.usage);
  assert.strictEqual(Math.abs((meta.usage.cost as number) - 0.040) < 0.0001, true);
  assert.strictEqual((meta.usage.tokens as any).total, 6500);
});

test('SessionIndex: getSubagents parses object and number costs without NaN', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-subagent-test-'));
  const sessionsDir = path.join(tmpDir, 'sessions');
  fs.mkdirSync(sessionsDir, { recursive: true });

  t.after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  const parentBasename = 'main-sess.jsonl';
  const subFile = path.join(sessionsDir, 'worker-1.jsonl');

  const lines = [
    JSON.stringify({
      type: 'session',
      id: 'worker#1',
      parentSession: parentBasename,
      cwd: '/test',
    }),
    JSON.stringify({ type: 'session_info', name: 'worker#1' }),
    JSON.stringify({ type: 'model_change', modelId: 'gpt-6-luna' }),
    JSON.stringify({
      type: 'message',
      role: 'assistant',
      content: 'Subagent output completed.',
      usage: {
        cost: { total: 0.0175 },
      },
    }),
  ];

  fs.writeFileSync(subFile, lines.join('\n'), 'utf8');

  const index = new SessionIndex({
    sessionsDir,
    cachePath: path.join(tmpDir, 'cache.json'),
  });
  const subagents = await index.getSubagents('main-sess', path.join(sessionsDir, parentBasename));

  assert.strictEqual(subagents.length, 1);
  assert.strictEqual(subagents[0].id, 'worker#1');
  assert.strictEqual(subagents[0].model, 'gpt-6-luna');
  assert.strictEqual(subagents[0].cost, 0.0175);
  assert.strictEqual(Number.isNaN(subagents[0].cost), false);
});
