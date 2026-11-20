import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { prepareDevHome } from './run-dev-app.mjs';

function sandbox() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-dev-home-'));
  return { root, releaseHome: path.join(root, '.piframe'), devHome: path.join(root, '.piframe-dev') };
}

test('dev home shares release attachments and copies settings once', () => {
  const { root, releaseHome, devHome } = sandbox();
  try {
    fs.mkdirSync(path.join(releaseHome, 'blobs', 'blob_old'), { recursive: true });
    fs.writeFileSync(path.join(releaseHome, 'blobs', 'blob_old', 'a.png'), 'img');
    fs.writeFileSync(path.join(releaseHome, 'config.json'), '{"workerIdleTimeoutMs":1}');

    prepareDevHome({ releaseHome, devHome });
    assert.equal(fs.readFileSync(path.join(devHome, 'blobs', 'blob_old', 'a.png'), 'utf8'), 'img');
    assert.equal(fs.readFileSync(path.join(devHome, 'config.json'), 'utf8'), '{"workerIdleTimeoutMs":1}');

    // Dev edits its own settings; a second run must not overwrite them with the release copy.
    fs.writeFileSync(path.join(devHome, 'config.json'), '{"workerIdleTimeoutMs":2}');
    prepareDevHome({ releaseHome, devHome });
    assert.equal(fs.readFileSync(path.join(devHome, 'config.json'), 'utf8'), '{"workerIdleTimeoutMs":2}');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('dev home never creates runtime files, so the release daemon lock and token stay untouched', () => {
  const { root, releaseHome, devHome } = sandbox();
  try {
    fs.mkdirSync(path.join(releaseHome, 'runtime'), { recursive: true });
    fs.writeFileSync(path.join(releaseHome, 'runtime', 'daemon.lock'), '123');
    prepareDevHome({ releaseHome, devHome });
    assert.equal(fs.existsSync(path.join(devHome, 'runtime')), false);
    assert.equal(fs.readFileSync(path.join(releaseHome, 'runtime', 'daemon.lock'), 'utf8'), '123');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
