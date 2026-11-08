import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import {
  readSettingsFile,
  writeJsonAtomicallyWithBackup,
  applyAgentSettingsChanges,
} from '../settingsWriter.js';
import { acquireLock } from '../lockfile.js';

function createTempDir(prefix: string): { dir: string; cleanup: () => void } {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  return {
    dir,
    cleanup: () => {
      try {
        fs.rmSync(dir, { recursive: true, force: true });
      } catch {}
    },
  };
}

test('readSettingsFile: parses valid JSON and throws AGENTS_CONFIG_UNREADABLE on invalid JSON', () => {
  const { dir, cleanup } = createTempDir('pi-test-read-');
  try {
    const validFile = path.join(dir, 'valid.json');
    fs.writeFileSync(validFile, '{"key": "value", "number": 42}');
    const parsed = readSettingsFile(validFile);
    assert.deepEqual(parsed, { key: 'value', number: 42 });

    const invalidFile = path.join(dir, 'invalid.json');
    fs.writeFileSync(invalidFile, '{"broken json: true');
    assert.throws(
      () => readSettingsFile(invalidFile),
      (err: any) => err?.code === 'AGENTS_CONFIG_UNREADABLE'
    );

    const nonExistent = path.join(dir, 'does-not-exist.json');
    assert.deepEqual(readSettingsFile(nonExistent), {});
  } finally {
    cleanup();
  }
});

test('writeJsonAtomicallyWithBackup: creates backup and preserves existing file permissions', async () => {
  const { dir, cleanup } = createTempDir('pi-test-write-');
  try {
    const targetFile = path.join(dir, 'settings.json');
    fs.writeFileSync(targetFile, JSON.stringify({ initial: true }), { mode: 0o600 });

    await writeJsonAtomicallyWithBackup(targetFile, { updated: true });

    // Backup exists
    const backupFile = `${targetFile}.piframe-backup`;
    assert.ok(fs.existsSync(backupFile));
    assert.deepEqual(JSON.parse(fs.readFileSync(backupFile, 'utf8')), { initial: true });

    // Target updated
    assert.deepEqual(JSON.parse(fs.readFileSync(targetFile, 'utf8')), { updated: true });
  } finally {
    cleanup();
  }
});

test('lock contention: fresh lock times out with AGENTS_CONFIG_LOCKED; stale lock is recovered', async () => {
  const { dir, cleanup } = createTempDir('pi-test-lock-');
  try {
    const targetFile = path.join(dir, 'settings.json');
    fs.writeFileSync(targetFile, '{}');

    // 1. Manually hold a fresh lock
    const releaseLock = await acquireLock(targetFile, { staleMs: 10_000 });

    // Concurrent write attempts should time out
    await assert.rejects(
      async () => {
        await writeJsonAtomicallyWithBackup(
          targetFile,
          { fail: true },
          { maxAttempts: 3, delayMs: 10, staleMs: 10_000 }
        );
      },
      (err: any) => err?.code === 'AGENTS_CONFIG_LOCKED'
    );

    // Release held lock
    releaseLock();

    // Now write succeeds
    await writeJsonAtomicallyWithBackup(targetFile, { success: true });
    assert.deepEqual(JSON.parse(fs.readFileSync(targetFile, 'utf8')), { success: true });

    // 2. Create a simulated stale lock (mtime in the past)
    const lockDir = `${targetFile}.lock`;
    fs.mkdirSync(lockDir, { recursive: true });
    const pastTime = new Date(Date.now() - 30_000);
    fs.utimesSync(lockDir, pastTime, pastTime);

    // Write should detect stale lock, break it, and succeed
    await writeJsonAtomicallyWithBackup(
      targetFile,
      { staleRecovered: true },
      { maxAttempts: 5, delayMs: 10, staleMs: 5_000 }
    );
    assert.deepEqual(JSON.parse(fs.readFileSync(targetFile, 'utf8')), { staleRecovered: true });
  } finally {
    cleanup();
  }
});

test('applyAgentSettingsChanges: preserves unrelated keys, writes sessionDefaults, agentOverrides, and context extension', async () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-writer-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-writer-piframe-');

  try {
    const settingsPath = path.join(agentDir, 'settings.json');
    const initialSettings = {
      unrelatedKey: 'preserveMe',
      enabledModels: ['anthropic/*'],
      subagents: {
        unrelatedSubagentKey: 'keepMe',
        agentOverrides: {
          worker: {
            customField: 'preserved',
            tools: 'read, write',
          },
        },
      },
    };
    fs.writeFileSync(settingsPath, JSON.stringify(initialSettings, null, 2));

    // Apply updates:
    // 1. sessionDefaults
    // 2. subagentDefaults
    // 3. agent worker model, thinking, contextLimit
    await applyAgentSettingsChanges(agentDir, piframeDir, [
      {
        kind: 'sessionDefaults',
        model: 'anthropic/claude-3-5-sonnet',
        thinking: 'medium',
      },
      {
        kind: 'subagentDefaults',
        model: 'anthropic/claude-3-5-haiku',
        thinking: 'low',
      },
      {
        kind: 'agent',
        name: 'worker',
        model: 'anthropic/claude-3-5-sonnet:high',
        thinking: 'high',
        contextLimit: 64000,
      },
    ]);

    const updated = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));

    // Check sessionDefaults
    assert.equal(updated.defaultProvider, 'anthropic');
    assert.equal(updated.defaultModel, 'claude-3-5-sonnet');
    assert.equal(updated.defaultThinkingLevel, 'medium');

    // Check unrelated top-level key preserved
    assert.equal(updated.unrelatedKey, 'preserveMe');
    assert.deepEqual(updated.enabledModels, ['anthropic/*']);

    // Check subagentDefaults
    assert.equal(updated.subagents.defaultModel, 'anthropic/claude-3-5-haiku');
    assert.equal(updated.subagents.defaultThinking, 'low');
    assert.equal(updated.subagents.unrelatedSubagentKey, 'keepMe');

    // Check worker overrides
    const workerOverride = updated.subagents.agentOverrides.worker;
    assert.equal(workerOverride.customField, 'preserved');
    assert.equal(workerOverride.tools, 'read, write');
    assert.equal(workerOverride.model, 'anthropic/claude-3-5-sonnet:high');
    assert.equal(workerOverride.thinking, 'high');
    assert.ok(Array.isArray(workerOverride.subagentOnlyExtensions));
    assert.equal(workerOverride.subagentOnlyExtensions.length, 1);
    assert.ok(workerOverride.subagentOnlyExtensions[0].endsWith('subagent-context-limit.mjs'));

    // Check subagent-context.json
    const contextJson = JSON.parse(
      fs.readFileSync(path.join(piframeDir, 'subagent-context.json'), 'utf8')
    );
    assert.equal(contextJson.worker, 64000);

    // Now clear worker context limit
    await applyAgentSettingsChanges(agentDir, piframeDir, [
      {
        kind: 'agent',
        name: 'worker',
        contextLimit: null,
      },
    ]);

    const afterContextClear = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    assert.equal(afterContextClear.subagents.agentOverrides.worker.subagentOnlyExtensions, undefined);
    const contextAfterClear = JSON.parse(
      fs.readFileSync(path.join(piframeDir, 'subagent-context.json'), 'utf8')
    );
    assert.equal(contextAfterClear.worker, undefined);
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});

test('readSettingsFile: strips UTF-8 BOM before JSON.parse, and writing does not add BOM', async () => {
  const { dir, cleanup } = createTempDir('pi-test-bom-');
  try {
    const bomFile = path.join(dir, 'with-bom.json');
    // Write UTF-8 with BOM: \uFEFF
    fs.writeFileSync(bomFile, '\uFEFF{"bomDetected": false, "status": "ok"}', 'utf8');

    const parsed = readSettingsFile(bomFile);
    assert.deepEqual(parsed, { bomDetected: false, status: 'ok' });

    // Write back and verify no BOM added
    const writtenFile = path.join(dir, 'written.json');
    await writeJsonAtomicallyWithBackup(writtenFile, { noBom: true });

    const rawBuffer = fs.readFileSync(writtenFile);
    // UTF-8 BOM is 0xEF, 0xBB, 0xBF
    assert.ok(rawBuffer[0] !== 0xef || rawBuffer[1] !== 0xbb || rawBuffer[2] !== 0xbf);
    assert.equal(rawBuffer.toString('utf8').charCodeAt(0) !== 0xfeff, true);
  } finally {
    cleanup();
  }
});

test('renameWithRetry on Windows: retries on transient errors and unlinks temp file on failure', async () => {
  const { dir, cleanup } = createTempDir('pi-test-rename-retry-');
  try {
    const targetFile = path.join(dir, 'settings.json');
    fs.writeFileSync(targetFile, '{}');

    // 1. Injected transient EBUSY error: fails twice, then succeeds
    let attempts = 0;
    const transientRename = (temp: string, target: string) => {
      attempts++;
      if (attempts < 3) {
        const err = new Error('Resource busy');
        throw Object.assign(err, { code: 'EBUSY' });
      }
      fs.renameSync(temp, target);
    };

    await writeJsonAtomicallyWithBackup(
      targetFile,
      { retrySuccess: true },
      { renameFn: transientRename }
    );
    assert.equal(attempts, 3);
    assert.deepEqual(JSON.parse(fs.readFileSync(targetFile, 'utf8')), { retrySuccess: true });

    // 2. Injected permanent EPERM error: fails all retries, unlinks temp file
    const permanentRename = () => {
      const err = new Error('Access denied');
      throw Object.assign(err, { code: 'EPERM' });
    };

    await assert.rejects(
      async () => {
        await writeJsonAtomicallyWithBackup(
          targetFile,
          { willFail: true },
          { renameFn: permanentRename, maxRetries: 3, delayMs: 5 }
        );
      },
      (err: any) => err?.code === 'EPERM'
    );

    // Verify temp file was unlinked
    const files = fs.readdirSync(dir);
    const tempFiles = files.filter((f) => f.includes('.tmp.'));
    assert.equal(tempFiles.length, 0);
  } finally {
    cleanup();
  }
});

test('stolen-lock scenario: aborts write with AGENTS_CONFIG_LOCKED and never deletes stolen lock', async () => {
  const { dir, cleanup } = createTempDir('pi-test-stolen-lock-');
  try {
    const targetFile = path.join(dir, 'settings.json');
    fs.writeFileSync(targetFile, JSON.stringify({ original: true }));

    // 1. Process A acquires lock
    const lockA = await acquireLock(targetFile, { staleMs: 5_000, updateIntervalMs: 100 });

    // 2. Simulate Process B stealing the lock by touching/updating the lock dir mtime
    const lockDir = `${targetFile}.lock`;
    assert.ok(fs.existsSync(lockDir));

    // Change lock dir mtime to simulate another owner
    const futureTime = new Date(Date.now() + 5_000);
    fs.utimesSync(lockDir, futureTime, futureTime);

    // 3. Process A attempts write using its lock handle -> should detect stolen lock
    await assert.rejects(
      async () => {
        await writeJsonAtomicallyWithBackup(
          targetFile,
          { overwritten: true },
          { lockHandle: lockA }
        );
      },
      (err: any) => err?.code === 'AGENTS_CONFIG_LOCKED'
    );

    // Verify target file was NOT overwritten
    assert.deepEqual(JSON.parse(fs.readFileSync(targetFile, 'utf8')), { original: true });

    // Verify no temp file left behind
    const files = fs.readdirSync(dir);
    assert.equal(files.filter((f) => f.includes('.tmp.')).length, 0);

    // 4. Process A releases its lock handle -> must NOT remove the stolen lock directory!
    lockA.release();
    assert.ok(fs.existsSync(lockDir), 'Stolen lock directory must NOT be removed by previous owner');

    // Clean up lock dir manually for temp dir cleanup
    try {
      fs.rmdirSync(lockDir);
    } catch {}
  } finally {
    cleanup();
  }
});

test('lock mtime tolerance: sub-millisecond differences (< 1ms) preserve ownership; changes >= 1ms detect compromised lock', async () => {
  const { dir, cleanup } = createTempDir('pi-test-mtime-tolerance-');
  try {
    const targetFile = path.join(dir, 'settings.json');
    fs.writeFileSync(targetFile, JSON.stringify({ original: true }));
    const lockDir = `${targetFile}.lock`;

    // 1. Process acquires lock
    const lock = await acquireLock(targetFile, { staleMs: 5_000, updateIntervalMs: 500 });
    assert.ok(fs.existsSync(lockDir));

    // Ownership check passes initially (< 1ms tolerance)
    assert.doesNotThrow(() => lock.check());
    assert.equal(lock.isCompromised(), false);

    // 2. Tolerance: another check with identical or < 1ms delta succeeds
    assert.doesNotThrow(() => lock.check());

    // 3. Stolen lock: external modification advances mtime by >= 1ms (2000ms)
    const futureTime = new Date(Date.now() + 2_000);
    fs.utimesSync(lockDir, futureTime, futureTime);

    // check() must detect the stolen lock and throw AGENTS_CONFIG_LOCKED
    assert.throws(
      () => lock.check(),
      (err: any) => err?.code === 'AGENTS_CONFIG_LOCKED'
    );
    assert.equal(lock.isCompromised(), true);

    // release() must NOT remove the compromised lock directory
    lock.release();
    assert.ok(fs.existsSync(lockDir), 'Stolen lock directory must remain on disk');

    try {
      fs.rmdirSync(lockDir);
    } catch {}

    // 4. Normal acquisition and release with mtime matching (< 1ms) cleanly removes directory
    const normalLock = await acquireLock(targetFile, { staleMs: 5_000 });
    assert.ok(fs.existsSync(lockDir));
    normalLock.release();
    assert.ok(!fs.existsSync(lockDir), 'Normal lock must be cleaned up on release');
  } finally {
    cleanup();
  }
});

test('hold lock across entire read-modify-write: concurrent modification between read and write does not cause lost update', async () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-rmw-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-rmw-piframe-');

  try {
    const settingsPath = path.join(agentDir, 'settings.json');
    fs.writeFileSync(
      settingsPath,
      JSON.stringify(
        {
          initial: true,
          subagents: {
            agentOverrides: {
              worker: {
                model: 'model-a',
              },
            },
          },
        },
        null,
        2
      )
    );

    let writer2Started = false;
    let writer2Promise: Promise<any> | null = null;

    // Writer 1 updates worker thinking to 'high'
    // While Writer 1 holds the lock across read-modify-write, hookAfterRead triggers Writer 2
    const writer1Promise = applyAgentSettingsChanges(
      agentDir,
      piframeDir,
      [
        {
          kind: 'agent',
          name: 'worker',
          thinking: 'high',
        },
      ],
      {
        hookAfterRead: async () => {
          writer2Started = true;
          // Writer 2 updates worker model to 'model-b'
          writer2Promise = applyAgentSettingsChanges(
            agentDir,
            piframeDir,
            [
              {
                kind: 'agent',
                name: 'worker',
                model: 'model-b',
              },
            ],
            { maxAttempts: 50, delayMs: 20 }
          );
          // Wait a short time to verify Writer 2 is active and waiting for the lock
          await new Promise((resolve) => setTimeout(resolve, 50));
        },
      }
    );

    await writer1Promise;
    assert.ok(writer2Started);
    assert.ok(writer2Promise);
    await writer2Promise;

    // Both updates must be preserved: NO LOST UPDATE!
    const finalSettings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    assert.equal(finalSettings.initial, true);
    assert.equal(finalSettings.subagents.agentOverrides.worker.model, 'model-b');
    assert.equal(finalSettings.subagents.agentOverrides.worker.thinking, 'high');
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});

test('sessionDefaults: null removes both defaultProvider and defaultModel leaving other settings intact', async () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-sess-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-sess-piframe-');

  try {
    const settingsPath = path.join(agentDir, 'settings.json');
    fs.writeFileSync(
      settingsPath,
      JSON.stringify(
        {
          defaultProvider: 'anthropic',
          defaultModel: 'claude-3-5-sonnet',
          defaultThinkingLevel: 'high',
          customAppSetting: 'preserved',
        },
        null,
        2
      )
    );

    await applyAgentSettingsChanges(agentDir, piframeDir, [
      {
        kind: 'sessionDefaults',
        model: null,
      },
    ]);

    const updated = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    assert.equal(updated.defaultProvider, undefined);
    assert.equal(updated.defaultModel, undefined);
    assert.equal(updated.defaultThinkingLevel, 'high');
    assert.equal(updated.customAppSetting, 'preserved');
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});
