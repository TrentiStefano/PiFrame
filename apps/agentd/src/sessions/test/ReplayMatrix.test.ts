import test from 'node:test';
import * as assert from 'node:assert';
import { EventEmitter } from 'node:events';
import { SessionRegistry } from '../SessionRegistry.js';
import { ConnectionManager } from '../../server/wsServer.js';
import { Connection, type ConnectionSocket } from '../../server/connection.js';

/** A socket that keeps the JSON text of every frame the connection writes. */
class RecordingSocket extends EventEmitter implements ConnectionSocket {
  public readyState = 1;
  public sent: string[] = [];

  public send(data: string, cb: () => void): void {
    this.sent.push(data);
    cb();
  }

  public close(): void {
    this.readyState = 3;
  }
}

/** The fields this test reads from a frame the daemon wrote. */
interface CapturedFrame {
  type?: string;
  kind?: string;
  seq?: number;
  payload?: Record<string, unknown>;
}

const sockets = new WeakMap<Connection, RecordingSocket>();

function createMockConnection(): Connection {
  const socket = new RecordingSocket();
  const conn = new Connection({
    ws: socket,
    expectedToken: 'tok',
    daemonVersion: 'test',
    startedAt: Date.now(),
    piInfo: { path: 'pi', version: '0.85.1', supported: true },
    onCommand: async () => {},
    onClose: () => {}
  });
  sockets.set(conn, socket);
  return conn;
}

/** The frames a connection has written, in order. */
function framesOf(conn: Connection): CapturedFrame[] {
  return (sockets.get(conn)?.sent ?? []).map((text) => JSON.parse(text));
}

test('SessionRegistry: attachClient §4.6 replay matrix coverage', async () => {
  const registry = new SessionRegistry({
    piExecutablePath: process.execPath,
    capabilities: { version: '0.85.1', supported: true, modes: [], features: [] },
    workerIdleTimeoutMs: 1800000,
    connectionManager: new ConnectionManager()
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
  const conn1 = createMockConnection();
  await registry.attachClient(sessionId, conn1, null);

  assert.strictEqual(framesOf(conn1).length, 1);
  assert.strictEqual(framesOf(conn1)[0]!.kind, 'snapshot');
  assert.strictEqual(framesOf(conn1)[0]!.seq, 10);

  // ---------------------------------------------------------------------------
  // Case 2: Resume: lastSeq = 6 -> ack{resume} + events 7..10
  // ---------------------------------------------------------------------------
  const conn2 = createMockConnection();
  await registry.attachClient(sessionId, conn2, 6, 'att_cmd_2');

  assert.strictEqual(framesOf(conn2).length, 5); // 1 ack + 4 events (7, 8, 9, 10)
  assert.strictEqual(framesOf(conn2)[0]!.kind, 'ack');
  assert.strictEqual(framesOf(conn2)[0]!.payload?.state, 'resume');
  assert.strictEqual(framesOf(conn2)[1]!.seq, 7);
  assert.strictEqual(framesOf(conn2)[2]!.seq, 8);
  assert.strictEqual(framesOf(conn2)[3]!.seq, 9);
  assert.strictEqual(framesOf(conn2)[4]!.seq, 10);

  // ---------------------------------------------------------------------------
  // Case 3: Gap: simulate ring buffer window where minSeq has advanced
  // ---------------------------------------------------------------------------
  // Mock minSeq getter on journal to 5
  Object.defineProperty(session.journal, 'minSeq', { get: () => 5, configurable: true });
  const conn3 = createMockConnection();
  // lastSeq = 2 is < minSeq - 1 (4), so it has a gap!
  await registry.attachClient(sessionId, conn3, 2);

  assert.strictEqual(framesOf(conn3).length, 2);
  assert.strictEqual(framesOf(conn3)[0]!.kind, 'snapshot');
  assert.strictEqual(framesOf(conn3)[1]!.kind, 'event');
  assert.strictEqual(framesOf(conn3)[1]!.type, 'journal.gap');
  assert.strictEqual(framesOf(conn3)[1]!.payload?.fromSeq, 2);
  assert.strictEqual(framesOf(conn3)[1]!.payload?.toSeq, 5);

  // ---------------------------------------------------------------------------
  // Case 4: Reset: lastSeq > currentSeq (e.g. 15 > 10)
  // ---------------------------------------------------------------------------
  const conn4 = createMockConnection();
  await registry.attachClient(sessionId, conn4, 15);

  assert.strictEqual(framesOf(conn4).length, 2);
  assert.strictEqual(framesOf(conn4)[0]!.kind, 'snapshot');
  assert.strictEqual(framesOf(conn4)[1]!.kind, 'event');
  assert.strictEqual(framesOf(conn4)[1]!.type, 'journal.gap');
  assert.strictEqual(framesOf(conn4)[1]!.payload?.reset, true);

  await registry.closeAll();
});
