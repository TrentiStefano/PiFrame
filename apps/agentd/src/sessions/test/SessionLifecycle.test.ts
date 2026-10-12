import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { SessionIndex } from '../SessionIndex.js';
import { SessionRegistry } from '../SessionRegistry.js';
import { Session } from '../Session.js';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-session-lifecycle-'));
const previousHome = process.env.PI_CRUST_HOME;
process.env.PI_CRUST_HOME = path.join(root, 'crust');
test.after(() => {
  if (previousHome === undefined) delete process.env.PI_CRUST_HOME;
  else process.env.PI_CRUST_HOME = previousHome;
  fs.rmSync(root, { recursive: true, force: true });
});

const sessionsDir = path.join(root, 'sessions');
fs.mkdirSync(sessionsDir);
const sourceFile = path.join(sessionsDir, 'timestamp_external.jsonl');
const entries = [
  { type: 'session', id: 'external', cwd: process.cwd() },
  { type: 'message', id: 'user1', parentId: null, message: { role: 'user', content: 'Original question', timestamp: 1 } },
  { type: 'message', id: 'abandoned', parentId: 'user1', message: { role: 'assistant', content: 'Abandoned answer' } },
  { type: 'message', id: 'answer', parentId: 'user1', message: { role: 'assistant', content: [{ type: 'text', text: 'Current answer' }] } },
  { type: 'session_info', id: 'name1', parentId: 'answer', name: 'Terminal session' },
];
fs.writeFileSync(sourceFile, entries.map((e) => JSON.stringify(e)).join('\n') + '\n');
const workerFile = path.join(root, 'worker.cjs');
fs.writeFileSync(workerFile, `
require('fs').writeFileSync(${JSON.stringify(path.join(root, 'args.json'))}, JSON.stringify(process.argv));
let buffer = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  buffer += chunk;
  while (buffer.includes('\\n')) {
    const index = buffer.indexOf('\\n');
    const request = JSON.parse(buffer.slice(0, index));
    buffer = buffer.slice(index + 1);
    const idIndex = process.argv.indexOf('--session-id');
    const id = process.argv[idIndex + 1];
    const data = request.type === 'get_state'
      ? { sessionFile: ${JSON.stringify(path.join(root, 'managed'))} + '-' + id + '.jsonl', thinkingLevel: 'low' }
      : { entries: [], leafId: null };
    process.stdout.write(JSON.stringify({ type: 'response', id: request.id, command: request.type, success: true, data }) + '\\n');
  }
});
`);

function registry(checkTerminalOwner: (cwd: string) => Promise<boolean | null> = async () => false) {
  return new SessionRegistry({
    piExecutablePath: workerFile,
    capabilities: { version: '0.99.2', supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 0,
    connectionManager: { broadcast: () => {} } as any,
    checkTerminalOwner,
    sessionIndex: new SessionIndex({ sessionsDir, cachePath: path.join(root, 'index.json') }),
  });
}

test('SessionIndex parses canonical IDs, names, nested content and active branch', async () => {
  const index = new SessionIndex({ sessionsDir, cachePath: path.join(root, 'index.json') });
  const result = await index.scan(new Set(['external']));
  assert.equal(result[0].id, 'external');
  assert.equal(result[0].name, 'Terminal session');
  assert.equal(result[0].messageCount, 3);
  assert.equal(result[0].lastMessagePreview, 'Current answer');
  assert.equal((await index.scan(new Set(['external'])))[0].isActive, true);
  const transcript = index.readTranscript(sourceFile);
  assert.deepEqual(transcript.map((e) => e.id), ['user1', 'answer']);
});

test('SessionRegistry merges unsaved sessions and continues an inactive Pi session in place', async () => {
  const r = registry(async () => false);
  try {
    const created = await r.createSession({ cwd: root, name: 'New GUI session' });
    assert.ok((await r.listSessions()).some((s) => s.id === created.id));
    const external = await r.openSession('external');
    assert.equal(external.readOnly, false);
    assert.equal(external.entries.length, 2);
    assert.equal(external.worker, undefined);
    const worker = await r.ensureWorkerForSession('external');
    assert.ok(worker);
    const args = JSON.parse(fs.readFileSync(path.join(root, 'args.json'), 'utf8')) as string[];
    assert.deepEqual(args.slice(args.indexOf('--session'), args.indexOf('--session') + 2), ['--session', sourceFile]);
    await assert.rejects(r.openSession('missing'), /not found/);
  } finally { await r.closeAll(); }
});

test('an open terminal session remains read-only and requires an explicit copy', async () => {
  const r = registry(async () => true);
  try {
    const external = await r.openSession('external');
    assert.equal(external.readOnly, true);
    assert.equal(external.readOnlyReason, 'terminal');
    await assert.rejects(r.ensureWorkerForSession('external'), /read-only/);
    const copy = await r.cloneSession('external');
    assert.equal(copy.readOnly, false);
  } finally { await r.closeAll(); }
});

test('ambiguous terminal project requires explicit confirmation before direct continuation', async () => {
  const r = registry(async () => null);
  try {
    const session = await r.openSession('external');
    assert.equal(session.readOnly, true);
    assert.equal(session.readOnlyReason, 'unknown');
    await assert.rejects(r.continueSession('external'), /Confirm/);
    const continued = await r.continueSession('external', true);
    assert.equal(continued.readOnly, false);
    assert.equal(continued.allowAmbiguousTerminal, true);
    assert.ok(await r.ensureWorkerForSession('external'));
  } finally { await r.closeAll(); }
});

test('temporary AppData session projects do not enter the index', async () => {
  const tempFile = path.join(sessionsDir, 'timestamp_temp.jsonl');
  fs.writeFileSync(tempFile, [
    { type: 'session', id: 'temporary', cwd: path.join(os.tmpdir(), 'temporary-project') },
    { type: 'message', id: 'temp-message', parentId: null, message: { role: 'user', content: 'Temp' } },
  ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');
  const index = new SessionIndex({ sessionsDir, cachePath: path.join(root, 'temp-index.json') });
  const rows = await index.scan();
  assert.ok(rows.some((row) => row.id === 'external'));
  assert.ok(!rows.some((row) => row.id === 'temporary'));
});

test('workers initialize once, bind Pi persistence and clone without writing source', async () => {
  const r = registry();
  const before = fs.readFileSync(sourceFile, 'utf8');
  try {
    const created = await r.createSession({ cwd: root });
    const [first, second] = await Promise.all([
      r.ensureWorkerForSession(created.id), r.ensureWorkerForSession(created.id),
    ]);
    assert.equal(first, second);
    assert.ok(created.sessionFile?.includes(created.id));
    const clone = await r.cloneSession('external');
    assert.equal(clone.readOnly, false);
    assert.notEqual(clone.sessionFile, sourceFile);
    assert.equal(fs.readFileSync(sourceFile, 'utf8'), before);
  } finally { await r.closeAll(); }
});

test('worker replacement waits for pending shutdown and remains registered', async () => {
  const r = registry();
  try {
    const session = await r.createSession({ cwd: root });
    const supervisor = r.getSupervisor() as any;
    let release!: () => void;
    let alive = true;
    const oldWorker = {
      health: () => ({ alive }),
      stop: () => { alive = false; return new Promise<void>((resolve) => { release = resolve; }); }
    };
    supervisor.activeWorkers.set(session.id, oldWorker);
    const shutdown = supervisor.stopWorker(session.id);
    const replacement = r.ensureWorkerForSession(session.id);
    await Promise.resolve();
    await Promise.resolve();
    assert.equal(supervisor.startingWorkers.size, 0);
    release();
    await shutdown;
    const worker = await replacement;
    assert.equal(supervisor.activeWorkers.get(session.id), worker);
    assert.equal(await r.ensureWorkerForSession(session.id), worker);
  } finally { await r.closeAll(); }
});

test('daemon shutdown rejects replacement already waiting on worker stop', async () => {
  const r = registry();
  const session = await r.createSession({ cwd: root });
  const supervisor = r.getSupervisor() as any;
  let release!: () => void;
  supervisor.activeWorkers.set(session.id, {
    health: () => ({ alive: false }),
    stop: () => new Promise<void>((resolve) => { release = resolve; })
  });
  const idleStop = supervisor.stopWorker(session.id);
  const replacement = r.ensureWorkerForSession(session.id);
  const rejected = assert.rejects(replacement, /shutting down/);
  const shutdown = supervisor.stopAll();
  release();
  await Promise.all([idleStop, shutdown, rejected]);
  assert.equal(supervisor.activeWorkers.size, 0);
  assert.equal(supervisor.startingWorkers.size, 0);
  await r.closeAll();
});

test('external resume always snapshots unjournaled terminal file changes', async () => {
  const r = registry(async () => true);
  const original = fs.readFileSync(sourceFile);
  const messages: any[] = [];
  const conn = { id: 'reader', attachedSessions: new Set(), send: (message: any) => messages.push(message) } as any;
  try {
    await r.attachClient('external', conn, null);
    const previousSeq = messages[0].seq;
    fs.appendFileSync(sourceFile, JSON.stringify({ type: 'message', id: 'new-user', parentId: 'name1',
      message: { role: 'user', content: 'Terminal continued', timestamp: 2 } }) + '\n');
    messages.length = 0;
    await r.attachClient('external', conn, previousSeq);
    assert.equal(messages[0].kind, 'snapshot');
    assert.equal(messages[0].payload.transcript.entries.at(-1).content, 'Terminal continued');
  } finally {
    fs.writeFileSync(sourceFile, original);
    await r.closeAll();
  }
});

test('full snapshot preserves live text, thinking, tools, queue and UI requests', async () => {
  const s = new Session({ id: 'snapshot', cwd: root });
  s.dispatchPiEvent({ type: 'agent_start' });
  s.dispatchPiEvent({ type: 'message_start', message: { role: 'assistant' } });
  s.dispatchPiEvent({ type: 'message_update', assistantMessageEvent: { type: 'text_delta', delta: 'Hello', contentIndex: 0 } });
  s.dispatchPiEvent({ type: 'message_update', assistantMessageEvent: { type: 'thinking_delta', delta: 'Thinking', contentIndex: 1 } });
  s.dispatchPiEvent({ type: 'tool_execution_start', toolCallId: 'call1', toolName: 'read', args: { path: 'file' } });
  s.dispatchPiEvent({ type: 'queue_update', steering: ['next'], followUp: [] });
  s.dispatchPiEvent({ type: 'extension_ui_request', id: 'ui1', method: 'select', options: ['Yes', 'No'], timeout: 5000 });
  const snapshot = s.getSnapshot();
  assert.equal((snapshot.liveMessage as any).content[0].text, 'Hello');
  assert.equal((snapshot.liveMessage as any).content[1].thinking, 'Thinking');
  assert.equal(snapshot.activeTools?.length, 1);
  assert.deepEqual(snapshot.runtime.queue?.steering, ['next']);
  assert.equal(snapshot.pendingUiRequests[0].timeoutMs, 5000);
  assert.equal(snapshot.runtime.status, 'awaiting_user');
  s.dispatchPiEvent({ type: 'agent_settled' });
  assert.equal(s.getSnapshot().activeTools?.length, 0);
  await s.close();
});
