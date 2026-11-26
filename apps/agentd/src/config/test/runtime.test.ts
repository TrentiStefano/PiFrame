import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { cleanupRuntimeFiles, getDaemonJsonPath, getPidPath, getTokenPath, writeRuntimeInfo } from '../runtime.js';

function withTempHome(body: () => void): void {
  const previous = process.env.PI_FRAME_HOME;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-runtime-'));
  process.env.PI_FRAME_HOME = dir;
  try {
    body();
  } finally {
    if (previous === undefined) delete process.env.PI_FRAME_HOME;
    else process.env.PI_FRAME_HOME = previous;
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

// Regression for #103: the app replaces an outdated daemon and starts the new one at once. The old
// daemon's shutdown deleted the runtime files that the new daemon had already written, so the app
// lost the new daemon.
test('cleanup leaves the runtime files of another daemon in place', () => {
  withTempHome(() => {
    writeRuntimeInfo({ port: 4100, pid: process.pid + 1, version: '1.5.1', startedAt: Date.now(), protocol: 1 });
    fs.writeFileSync(getTokenPath(), 'token-of-the-new-daemon', 'utf8');

    cleanupRuntimeFiles();

    assert.ok(fs.existsSync(getDaemonJsonPath()));
    assert.ok(fs.existsSync(getPidPath()));
    assert.ok(fs.existsSync(getTokenPath()));
  });
});

test('cleanup removes this daemon runtime files', () => {
  withTempHome(() => {
    writeRuntimeInfo({ port: 4100, pid: process.pid, version: '1.5.1', startedAt: Date.now(), protocol: 1 });
    fs.writeFileSync(getTokenPath(), 'token', 'utf8');

    cleanupRuntimeFiles();

    assert.equal(fs.existsSync(getDaemonJsonPath()), false);
    assert.equal(fs.existsSync(getPidPath()), false);
    assert.equal(fs.existsSync(getTokenPath()), false);
  });
});
