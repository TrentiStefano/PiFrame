import test from 'node:test';
import * as assert from 'node:assert';
import { Session } from '../Session.js';
import { SessionRegistry } from '../SessionRegistry.js';

function createMockConnection(id: string) {
  const sentMessages: any[] = [];
  return {
    id,
    attachedSessions: new Set<string>(),
    send: (msg: any) => {
      sentMessages.push(msg);
    },
    sentMessages
  } as any;
}

test('SessionRegistry: attachClient §4.6 replay matrix coverage', async () => {
  const registry = new SessionRegistry({
    piExecutablePath: process.execPath,
    capabilities: { version: '0.85.1', supported: true, modes: [], features: [] },
    workerIdleTimeoutMs: 1800000,
    connectionManager: {
      broadcast: () => {},
      broadcastAll: () => {}
    } as any
  });

  const session = await registry.createSession({ name: 'Replay Matrix Test' });
  const sessionId = session.id;

  // Append 10 events to journal (seq 1 to 10)
  for (let i = 1; i <= 10; i++) {
    session.emitCustomEvent('text.delta', { contentIndex: 0, delta: `chunk_${i}` });
  }

  assert.strictEqual(session.journal.currentSeq, 10);
  assert.strictEqual(session.journal.minSeq, 1);

  // ---------------------------------------------------------------------------
  // Case 1: lastSeq == null -> Full Snapshot
  // ---------------------------------------------------------------------------
  const conn1 = createMockConnection('conn_1');
  await registry.attachClient(sessionId, conn1, null);

  assert.strictEqual(conn1.sentMessages.length, 1);
  assert.strictEqual(conn1.sentMessages[0].kind, 'snapshot');
  assert.strictEqual(conn1.sentMessages[0].seq, 10);

  // ---------------------------------------------------------------------------
  // Case 2: Resume: lastSeq = 6 -> ack{resume} + events 7..10
  // ---------------------------------------------------------------------------
  const conn2 = createMockConnection('conn_2');
  await registry.attachClient(sessionId, conn2, 6, 'att_cmd_2');

  assert.strictEqual(conn2.sentMessages.length, 5); // 1 ack + 4 events (7, 8, 9, 10)
  assert.strictEqual(conn2.sentMessages[0].kind, 'ack');
  assert.strictEqual(conn2.sentMessages[0].payload.state, 'resume');
  assert.strictEqual(conn2.sentMessages[1].seq, 7);
  assert.strictEqual(conn2.sentMessages[2].seq, 8);
  assert.strictEqual(conn2.sentMessages[3].seq, 9);
  assert.strictEqual(conn2.sentMessages[4].seq, 10);

  // ---------------------------------------------------------------------------
  // Case 3: Gap: simulate ring buffer window where minSeq has advanced
  // ---------------------------------------------------------------------------
  // Mock minSeq getter on journal to 5
  Object.defineProperty(session.journal, 'minSeq', { get: () => 5, configurable: true });
  const conn3 = createMockConnection('conn_3');
  // lastSeq = 2 is < minSeq - 1 (4), so it has a gap!
  await registry.attachClient(sessionId, conn3, 2);

  assert.strictEqual(conn3.sentMessages.length, 2);
  assert.strictEqual(conn3.sentMessages[0].kind, 'snapshot');
  assert.strictEqual(conn3.sentMessages[1].kind, 'event');
  assert.strictEqual(conn3.sentMessages[1].type, 'journal.gap');
  assert.strictEqual(conn3.sentMessages[1].payload.fromSeq, 2);
  assert.strictEqual(conn3.sentMessages[1].payload.toSeq, 5);

  // ---------------------------------------------------------------------------
  // Case 4: Reset: lastSeq > currentSeq (e.g. 15 > 10)
  // ---------------------------------------------------------------------------
  const conn4 = createMockConnection('conn_4');
  await registry.attachClient(sessionId, conn4, 15);

  assert.strictEqual(conn4.sentMessages.length, 2);
  assert.strictEqual(conn4.sentMessages[0].kind, 'snapshot');
  assert.strictEqual(conn4.sentMessages[1].kind, 'event');
  assert.strictEqual(conn4.sentMessages[1].type, 'journal.gap');
  assert.strictEqual(conn4.sentMessages[1].payload.reset, true);

  await registry.closeAll();
});
