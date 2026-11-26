import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { enableDaemonFileLog, reportSlowCommand, startDevCpuProfile, startEventLoopMonitor } from '../devLog.js';

function tempLogFile(): { dir: string; file: string } {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-devlog-'));
  return { dir, file: path.join(dir, 'daemon.log') };
}

test('event-loop monitor reports a block that is longer than the threshold', async () => {
  const reports: number[] = [];
  const stop = startEventLoopMonitor((ms) => reports.push(ms), { intervalMs: 20, thresholdMs: 100 });
  await new Promise((resolve) => setTimeout(resolve, 60));
  const until = Date.now() + 250;
  while (Date.now() < until) {
    /* block the loop on purpose */
  }
  await new Promise((resolve) => setTimeout(resolve, 60));
  stop();
  assert.ok(
    reports.some((ms) => ms >= 100),
    `expected a stall report, got ${JSON.stringify(reports)}`
  );
});

test('dev CPU profile is written after the requested seconds and stays off without the variable', async () => {
  const { dir } = tempLogFile();
  const profile = path.join(dir, 'cpu.cpuprofile');
  try {
    assert.equal(startDevCpuProfile({}, profile), false);
    const done = new Promise<string>((resolve) => {
      assert.equal(startDevCpuProfile({ PIFRAME_DEV_PROFILE_SECONDS: '0.2' }, profile, resolve), true);
    });
    const until = Date.now() + 50;
    while (Date.now() < until) {
      /* give the profiler something to sample */
    }
    await done;
    const parsed = JSON.parse(fs.readFileSync(profile, 'utf8'));
    assert.ok(Array.isArray(parsed.nodes) && parsed.nodes.length > 0);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

// #114: the timing evidence for #104 and #105 existed only in dev builds' log. Every daemon now keeps the
// documented runtime/daemon.log, with slow commands and loop stalls but without console output.
test('a release daemon logs slow commands but not console output', () => {
  const { dir, file } = tempLogFile();
  const originalLog = console.log;
  try {
    const stop = enableDaemonFileLog({}, file);
    console.log('[agentd] private detail');
    reportSlowCommand('agent.getModels', 's_1', 30720);
    stop();
    const content = fs.readFileSync(file, 'utf8');
    assert.match(content, /start --- daemon pid=\d+ ---/);
    assert.match(content, / slow command agent\.getModels session=s_1 took 30720ms/);
    assert.doesNotMatch(content, /private detail/);
  } finally {
    console.log = originalLog;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('the log rotates across a fixed number of files of a fixed size', () => {
  const { dir, file } = tempLogFile();
  try {
    const stop = enableDaemonFileLog({}, file, { maxBytes: 200, files: 3 });
    for (let i = 0; i < 40; i++) reportSlowCommand('session.list', undefined, 1000 + i);
    stop();
    const logs = fs.readdirSync(dir).sort();
    assert.deepEqual(logs, ['daemon.log', 'daemon.log.1', 'daemon.log.2']);
    for (const name of logs) assert.ok(fs.statSync(path.join(dir, name)).size <= 200, name);
    assert.match(fs.readFileSync(file, 'utf8'), /took 1039ms/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('slow commands are logged with their type and session only above the threshold', () => {
  const { dir, file } = tempLogFile();
  try {
    const stop = enableDaemonFileLog({ PIFRAME_DEV_LOG: '1' }, file);
    assert.ok(stop);
    reportSlowCommand('session.open', 's_1', 120);
    reportSlowCommand('session.create', undefined, 1400);
    stop();
    reportSlowCommand('session.list', undefined, 9000);
    const content = fs.readFileSync(file, 'utf8');
    assert.doesNotMatch(content, /session\.open/);
    assert.match(content, / slow command session\.create session=- took 1400ms/);
    assert.doesNotMatch(content, /session\.list/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('a dev daemon also mirrors console output into the log file', () => {
  const { dir, file } = tempLogFile();
  const originalLog = console.log;
  const originalWarn = console.warn;
  try {
    const stop = enableDaemonFileLog({ PIFRAME_DEV_LOG: '1' }, file);
    assert.ok(stop);
    console.log('[agentd] probe %s', 'alpha');
    console.warn('probe warning');
    stop();
    const content = fs.readFileSync(file, 'utf8');
    assert.match(content, /start --- daemon pid=\d+ ---/);
    assert.match(content, / log \[agentd\] probe alpha/);
    assert.match(content, / warn probe warning/);
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
