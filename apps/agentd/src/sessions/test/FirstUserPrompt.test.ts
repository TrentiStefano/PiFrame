import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { FIRST_PROMPT_MAX_LENGTH, SessionIndex } from '../SessionIndex.js';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-first-prompt-'));
test.after(() => fs.rmSync(root, { recursive: true, force: true }));

let counter = 0;
/** A fresh sessions folder and cache path, so each test starts cold. */
function makeFolder(): { dir: string; cache: string } {
  const base = path.join(root, `case-${counter++}`);
  const dir = path.join(base, 'sessions');
  fs.mkdirSync(dir, { recursive: true });
  return { dir, cache: path.join(base, 'index.json') };
}

function writeSession(dir: string, id: string, messages: unknown[]): string {
  const file = path.join(dir, `timestamp_${id}.jsonl`);
  const rows = [{ type: 'session', id, cwd: process.cwd() }, ...messages];
  fs.writeFileSync(file, rows.map((row) => JSON.stringify(row)).join('\n') + '\n');
  return file;
}

const withPrompt = [
  { type: 'message', message: { role: 'assistant', content: 'Earlier reply' } },
  {
    type: 'message',
    message: { role: 'user', content: [{ type: 'text', text: '  Fix the\n\n  parser   ' }] }
  },
  { type: 'message', message: { role: 'user', content: 'Second question' } }
];

test('full scan takes the first user prompt, flattened and trimmed', async () => {
  const { dir, cache } = makeFolder();
  writeSession(dir, 'prompted', withPrompt);
  const index = new SessionIndex({ sessionsDir: dir, cachePath: cache });
  const [session] = await index.scan(new Set());
  assert.equal(session!.id, 'prompted');
  assert.equal(session!.firstUserPrompt, 'Fix the parser');
});

test('a prompt longer than the limit is cut to FIRST_PROMPT_MAX_LENGTH', async () => {
  const { dir, cache } = makeFolder();
  const long = 'word '.repeat(100);
  writeSession(dir, 'long', [{ type: 'message', message: { role: 'user', content: long } }]);
  const index = new SessionIndex({ sessionsDir: dir, cachePath: cache });
  const [session] = await index.scan(new Set());
  assert.equal(FIRST_PROMPT_MAX_LENGTH, 120);
  assert.equal(session!.firstUserPrompt?.length, FIRST_PROMPT_MAX_LENGTH);
  assert.ok(long.startsWith(session!.firstUserPrompt!));
});

test('a session with no user message has an empty first prompt, not a missing one', async () => {
  const { dir, cache } = makeFolder();
  writeSession(dir, 'silent', [{ type: 'message', message: { role: 'assistant', content: 'Only an answer' } }]);
  const index = new SessionIndex({ sessionsDir: dir, cachePath: cache });
  const [session] = await index.scan(new Set());
  assert.equal(session!.firstUserPrompt, '');
});

test('fast scan of a cold folder also reports the first user prompt', async () => {
  const { dir, cache } = makeFolder();
  writeSession(dir, 'fast', withPrompt);
  const index = new SessionIndex({ sessionsDir: dir, cachePath: cache });
  const fast = await index.scanFast();
  const session = fast.sessions.find((s) => s.id === 'fast');
  assert.ok(session, 'session is listed by the fast scan');
  assert.equal(session.firstUserPrompt, 'Fix the parser');
});

test('cache entries written before the field existed are read again once', async () => {
  const { dir, cache } = makeFolder();
  writeSession(dir, 'migrated', withPrompt);
  await new SessionIndex({ sessionsDir: dir, cachePath: cache }).scan(new Set());

  const saved = JSON.parse(fs.readFileSync(cache, 'utf8')) as Array<{ summary: Record<string, unknown> }>;
  assert.ok(saved.length > 0, 'index cache was written');
  for (const item of saved) delete item.summary.firstUserPrompt;
  fs.writeFileSync(cache, JSON.stringify(saved));

  const [session] = await new SessionIndex({ sessionsDir: dir, cachePath: cache }).scan(new Set());
  assert.equal(session!.firstUserPrompt, 'Fix the parser');
});
