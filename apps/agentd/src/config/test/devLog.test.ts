import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { enableDevFileLog, reportSlowCommand, startDevCpuProfile, startEventLoopMonitor } from '../devLog.js';

function tempLogFile(): { dir: string; file: string } {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-devlog-'));
  return { dir, file: path.join(dir, 'daemon.log') };
}

test('event-loop monitor reports a block that is longer than the threshold', async () => {
  const reports: number[] = [];
  const stop = startEventLoopMonitor((ms) => reports.push(ms), { intervalMs: 20, thresholdMs: 100 });
  await new Promise((resolve) => setTimeout(resolve, 60));
  const until = Date.now() + 250;
  while (Date.now() < until) { /* block the loop on purpose */ }
  await new Promise((resolve) => setTimeout(resolve, 60));
  stop();
  assert.ok(reports.some((ms) => ms >= 100), `expected a stall report, got ${JSON.stringify(reports)}`);
});

test('dev CPU profile is written after the requested seconds and stays off without the variable', async () => {
  const { dir, file } = tempLogFile();
  const profile = path.join(dir, 'cpu.cpuprofile');
  try {
    assert.equal(startDevCpuProfile({}, profile), false);
    const done = new Promise<string>((resolve) => {
      assert.equal(startDevCpuProfile({ PIFRAME_DEV_PROFILE_SECONDS: '0.2' }, profile, resolve), true);
    });
    const until = Date.now() + 50;
    while (Date.now() < until) { /* give the profiler something to sample */ }
    await done;
    const parsed = JSON.parse(fs.readFileSync(profile, 'utf8'));
    assert.ok(Array.isArray(parsed.nodes) && parsed.nodes.length > 0);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('dev file log is off unless PIFRAME_DEV_LOG=1, so release daemons write nothing', () => {
  const { dir, file } = tempLogFile();
  try {
    const stop = enableDevFileLog({}, file);
    assert.equal(stop, null);
    assert.equal(fs.existsSync(file), false);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('slow commands are logged with their type and session only above the threshold', () => {
  const { dir, file } = tempLogFile();
  try {
    const stop = enableDevFileLog({ PIFRAME_DEV_LOG: '1' }, file);
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

test('dev file log mirrors console output into the log file', () => {
  const { dir, file } = tempLogFile();
  const originalLog = console.log;
  const originalWarn = console.warn;
  try {
    const stop = enableDevFileLog({ PIFRAME_DEV_LOG: '1' }, file);
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
