// Large pinned sessions (100+ MB) produced snapshot frames above the 128 MB
// WebSocket backpressure limit, so the connection closed with 4009 and the app
// reconnected forever. The journal also kept every pretty-printed snapshot
// checkpoint, filling ~/.piframe/journal with tens of gigabytes.
import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { EventJournal } from '../EventJournal.js';
import { Session } from '../../sessions/Session.js';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-snapshot-retention-'));
const previousHome = process.env.PI_FRAME_HOME;
process.env.PI_FRAME_HOME = root;
test.after(() => {
  if (previousHome === undefined) delete process.env.PI_FRAME_HOME;
  else process.env.PI_FRAME_HOME = previousHome;
  fs.rmSync(root, { recursive: true, force: true });
});

const snapshotFiles = (sessionId: string) =>
  fs
    .readdirSync(path.join(root, 'journal', sessionId))
    .filter((name) => /^snapshot\.\d+\.json$/.test(name))
    .sort();

test('a session snapshot carries only the latest 100 entries and caps huge text fields', () => {
  const session = new Session({ id: 's_big', cwd: root });
  const huge = 'x'.repeat(2 * 1024 * 1024);
  session.entries = Array.from({ length: 1500 }, (_, i) => ({
    id: `e${i}`,
    role: i % 2 === 0 ? 'user' : 'assistant',
    text: i === 1499 ? huge : `entry ${i}`,
    thinking: i === 1499 ? huge : undefined
  }));

  const snapshot = session.getSnapshot();
  const entries = snapshot.transcript.entries;
  assert.equal(entries.length, 100);
  assert.equal(entries[0]!.id, 'e1400', 'the most recent entries are kept');
  assert.equal(entries[99]!.id, 'e1499');
  assert.equal(snapshot.transcript.totalEntries, 1500);
  assert.equal(snapshot.transcript.hasMore, true, 'older history is paged in on demand');
  const last = entries[99];
  assert.ok(typeof last!.text === 'string' && last!.text.length < 300 * 1024, 'oversized text is capped');
  assert.ok(typeof last!.thinking === 'string' && last!.thinking.length < 300 * 1024, 'oversized thinking is capped');
  assert.ok(Buffer.byteLength(JSON.stringify(snapshot)) < 1024 * 1024, 'the frame stays far below the 128 MB limit');
  void session.journal.close();
});

test('the journal keeps only the two newest snapshot checkpoints, as compact JSON', async () => {
  const sessionId = 's_checkpoints';
  const journalDir = path.join(root, 'journal', sessionId);
  fs.mkdirSync(journalDir, { recursive: true });
  // Checkpoints left behind by an older daemon are cleaned up on start.
  for (const seq of [5, 10, 15, 20]) {
    fs.writeFileSync(path.join(journalDir, `snapshot.${seq}.json`), JSON.stringify({ seq }, null, 2));
  }
  const first = new EventJournal({ sessionId, snapshotEvery: 1000 });
  assert.deepEqual(snapshotFiles(sessionId), ['snapshot.15.json', 'snapshot.20.json']);
  await first.close();

  const session = new Session({ id: 's_context', cwd: root });
  session.entries = [{ id: 'e1', role: 'user', text: 'hello' }];
  const journal = new EventJournal({
    sessionId,
    snapshotEvery: 25,
    getContext: () => session.getSnapshotContext()
  });
  for (let i = 0; i < 150; i++) {
    journal.append({ type: 'text.delta', payload: { contentIndex: 0, delta: `chunk_${i}` } });
  }
  const files = snapshotFiles(sessionId);
  assert.equal(files.length, 2, `only two checkpoints remain, found ${files.join(', ')}`);
  const seqs = files.map((name) => Number(/\d+/.exec(name)?.[0])).sort((a, b) => a - b);
  assert.deepEqual(seqs, [125, 150]);
  const written = fs.readFileSync(path.join(journalDir, `snapshot.${seqs[1]}.json`), 'utf8');
  assert.ok(!written.includes('\n'), 'snapshots are written without indentation');
  await journal.close();
  await session.journal.close();
});
