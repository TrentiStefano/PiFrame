import test from 'node:test';
import * as assert from 'node:assert/strict';
import { EventJournal } from '../EventJournal.js';

test('EventJournal: strictly monotonic seq numbers under rapid sequential appends', () => {
  const journal = new EventJournal({
    sessionId: `test_${Date.now()}`,
    maxEvents: 50
  });

  const count = 100;
  for (let i = 0; i < count; i++) {
    const evt = journal.append({
      type: 'text.delta',
      payload: { contentIndex: 0, delta: `chunk_${i}` }
    });
    assert.equal(evt.seq, i + 1);
  }

  assert.equal(journal.currentSeq, 100);

  // Range within ring buffer
  const range = journal.getRange(80, 90);
  assert.equal(range.length, 11);
  assert.equal(range[0].seq, 80);
  assert.equal(range[10].seq, 90);

  journal.close();
});
