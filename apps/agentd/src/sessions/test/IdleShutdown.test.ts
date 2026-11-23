// pi-subagents runs background agents inside the Pi worker. The idle shutdown
// stopped a settled worker without checking for them, killing a running agent
// with no result, so the main agent waited on it forever.
import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { Session } from '../Session.js';
import { WorkerSupervisor } from '../WorkerSupervisor.js';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-idle-shutdown-'));
const previousHome = process.env.PI_FRAME_HOME;
process.env.PI_FRAME_HOME = path.join(root, 'frame');
test.after(() => {
  if (previousHome === undefined) delete process.env.PI_FRAME_HOME;
  else process.env.PI_FRAME_HOME = previousHome;
  fs.rmSync(root, { recursive: true, force: true });
});

const sessionFile = path.join(root, 'session.jsonl');
fs.writeFileSync(sessionFile, JSON.stringify({ type: 'session', id: 's_idle', cwd: root }) + '\n');
const workerFile = path.join(root, 'worker.cjs');
fs.writeFileSync(
  workerFile,
  `
let buffer = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  buffer += chunk;
  while (buffer.includes('\\n')) {
    const index = buffer.indexOf('\\n');
    const request = JSON.parse(buffer.slice(0, index));
    buffer = buffer.slice(index + 1);
    const data = request.type === 'get_state'
      ? { sessionFile: ${JSON.stringify(sessionFile)} }
      : { entries: [], leafId: null };
    process.stdout.write(JSON.stringify({ type: 'response', id: request.id, command: request.type, success: true, data }) + '\\n');
  }
});
`
);

const bridgeReport = (anyRunning: boolean) => ({
  type: 'extension_ui_request',
  method: 'setStatus',
  statusKey: 'piframe-subagents',
  statusText: JSON.stringify({
    v: 1,
    available: true,
    anyRunning,
    idleSince: anyRunning ? null : 5,
    bridgeStartedAt: 1,
    agents: [{ id: 'agent-1', status: anyRunning ? 'running' : 'completed' }]
  })
});

test('the idle shutdown keeps a worker alive while a background agent runs in it', async (t) => {
  // The idle timer runs on mocked time: it fires only when the test advances
  // the clock, never while the worker is still starting on a loaded machine.
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const idleTimeoutMs = 60_000;
  const supervisor = new WorkerSupervisor({
    piExecutablePath: workerFile,
    capabilities: { version: '0.99.2', supported: true, modes: ['rpc'], features: [] },
    defaultIdleTimeoutMs: idleTimeoutMs,
    checkTerminalOwner: async () => false
  });
  const session = new Session({ id: 's_idle', cwd: root, sessionFile });
  try {
    await supervisor.ensureWorker(session);
    session.status = 'settled';
    session.dispatchPiEvent(bridgeReport(true));

    // The idle check stops a worker synchronously (it kills the process
    // before its first await), so liveWorker answers right after the tick.
    t.mock.timers.tick(idleTimeoutMs);
    assert.ok(supervisor.liveWorker(session.id), 'a settled main agent with a running background agent is not idle');
    t.mock.timers.tick(idleTimeoutMs);
    assert.ok(supervisor.liveWorker(session.id), 'the check is repeated, and still waits');

    session.dispatchPiEvent(bridgeReport(false));
    t.mock.timers.tick(idleTimeoutMs);
    assert.equal(supervisor.liveWorker(session.id), undefined, 'once nothing runs the idle worker stops');
  } finally {
    t.mock.timers.reset();
    await supervisor.stopAll(500);
    await session.journal.close();
  }
});
