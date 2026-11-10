import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { spawn } from 'node:child_process';
import { hasInteractivePiInCwd } from '../PiTerminalDetector.js';

test('detects an interactive Pi CLI process in the session project', { timeout: 15000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-terminal-owner-'));
  const cli = path.join(root, 'node_modules', '@earendil-works', 'pi-coding-agent', 'dist', 'bundle', 'cli.js');
  fs.mkdirSync(path.dirname(cli), { recursive: true });
  fs.writeFileSync(cli, 'setInterval(() => {}, 1000);');
  const child = spawn(process.execPath, [cli], {
    cwd: root,
    stdio: 'ignore',
    windowsHide: true,
  });
  try {
    await new Promise<void>((resolve, reject) => {
      child.once('spawn', resolve);
      child.once('error', reject);
    });
    assert.equal(await hasInteractivePiInCwd(root), null);
    assert.equal(await hasInteractivePiInCwd(path.dirname(root)), false);
  } finally {
    child.kill();
    await new Promise<void>((resolve) => child.once('exit', () => resolve()));
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('matches explicit terminal session path exactly', { timeout: 15000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-terminal-session-'));
  const cli = path.join(root, 'node_modules', '@earendil-works', 'pi-coding-agent', 'dist', 'bundle', 'cli.js');
  const sessionFile = path.join(root, 'session.jsonl');
  fs.mkdirSync(path.dirname(cli), { recursive: true });
  fs.writeFileSync(cli, 'setInterval(() => {}, 1000);');
  fs.writeFileSync(sessionFile, '{}\\n');
  const child = spawn(process.execPath, [cli, '--session', sessionFile], {
    cwd: root,
    stdio: 'ignore',
    windowsHide: true,
  });
  try {
    await new Promise<void>((resolve, reject) => {
      child.once('spawn', resolve);
      child.once('error', reject);
    });
    assert.equal(await hasInteractivePiInCwd(root, sessionFile, 'session'), true);
    assert.equal(await hasInteractivePiInCwd(root, path.join(root, 'other.jsonl'), 'other'), false);
  } finally {
    child.kill();
    await new Promise<void>((resolve) => child.once('exit', () => resolve()));
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('concurrent checks share one process scan and a later check scans again', { timeout: 30000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-terminal-shared-'));
  const cli = path.join(root, 'node_modules', '@earendil-works', 'pi-coding-agent', 'dist', 'bundle', 'cli.js');
  fs.mkdirSync(path.dirname(cli), { recursive: true });
  fs.writeFileSync(cli, 'setInterval(() => {}, 1000);');
  try {
    const started = Date.now();
    const results = await Promise.all(Array.from({ length: 4 }, () => hasInteractivePiInCwd(root)));
    const sharedMs = Date.now() - started;
    assert.deepEqual(results, [false, false, false, false]);

    // A terminal opened after the shared scan finished must still be detected.
    const child = spawn(process.execPath, [cli], { cwd: root, stdio: 'ignore', windowsHide: true });
    try {
      await new Promise<void>((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
      const single = Date.now();
      assert.equal(await hasInteractivePiInCwd(root), null);
      // Four shared checks must cost about one scan, not four.
      assert.ok(sharedMs < (Date.now() - single) * 2.5, `shared=${sharedMs}ms`);
    } finally {
      child.kill();
      await new Promise<void>((resolve) => child.once('exit', () => resolve()));
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('ignores Pi RPC workers because daemon owns those session writes', { timeout: 15000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-rpc-owner-'));
  const cli = path.join(root, 'node_modules', '@earendil-works', 'pi-coding-agent', 'dist', 'bundle', 'cli.js');
  fs.mkdirSync(path.dirname(cli), { recursive: true });
  fs.writeFileSync(cli, 'setInterval(() => {}, 1000);');
  const child = spawn(process.execPath, [cli, '--mode', 'rpc'], {
    cwd: root,
    stdio: 'ignore',
    windowsHide: true,
  });
  try {
    await new Promise<void>((resolve, reject) => {
      child.once('spawn', resolve);
      child.once('error', reject);
    });
    assert.equal(await hasInteractivePiInCwd(root), false);
  } finally {
    child.kill();
    await new Promise<void>((resolve) => child.once('exit', () => resolve()));
    fs.rmSync(root, { recursive: true, force: true });
  }
});
