import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { pathToFileURL } from 'node:url';
import {
  ensureSubagentContextLimitExtension,
  ensureSubagentContextLimitExtensionIfReferenced,
  generateSubagentContextLimitSource,
  subagentContextLimitExtension,
} from '../subagentContextLimitExtension.js';

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

test('SubagentContextLimitExtension: generates .mjs extension file and can be dynamically imported', async () => {
  const { dir: piframeDir, cleanup } = createTempDir('pi-test-ext-dir-');
  try {
    const filePath = ensureSubagentContextLimitExtension(piframeDir);
    assert.ok(fs.existsSync(filePath));
    assert.ok(filePath.endsWith('subagent-context-limit.mjs'));

    // Dynamic import to verify it is valid JavaScript
    const fileUrl = pathToFileURL(filePath).href;
    const module = await import(fileUrl);
    assert.equal(typeof module.default, 'function');
  } finally {
    cleanup();
  }
});

test('subagentContextLimitExtension logic: applies limit only when model has tiers, limit < window, and tag matches', async () => {
  const { dir: piframeDir, cleanup } = createTempDir('pi-test-ext-logic-');
  const prevEnv = process.env.PI_FRAME_HOME;
  process.env.PI_FRAME_HOME = piframeDir;

  try {
    // 1. Setup subagent-context.json with worker=64000
    fs.writeFileSync(
      path.join(piframeDir, 'subagent-context.json'),
      JSON.stringify({ worker: 64000 })
    );

    let registeredHandlers: Record<string, (event: any, ctx: any) => Promise<void>> = {};
    let modelSetCalls: any[] = [];

    const fakePi = {
      on: (event: string, handler: any) => {
        registeredHandlers[event] = handler;
      },
      setModel: async (model: any) => {
        modelSetCalls.push(model);
        return true;
      },
    };

    subagentContextLimitExtension(fakePi);

    assert.ok(registeredHandlers['session_start']);
    assert.ok(registeredHandlers['before_agent_start']);

    // Case A: No active_agent tag -> NO setModel call
    await registeredHandlers['session_start'](
      { systemPrompt: 'Standard instructions without active agent tag' },
      {
        model: {
          id: 'claude-3-5-sonnet',
          contextWindow: 200000,
          cost: { tiers: [{ inputTokensAbove: 64000 }] },
        },
      }
    );
    assert.equal(modelSetCalls.length, 0);

    // Case B: Active agent tag for 'scout' which has no configured limit -> NO setModel call
    await registeredHandlers['before_agent_start'](
      { systemPrompt: '<active_agent name="scout"/>\n\nPrompt' },
      {
        model: {
          id: 'claude-3-5-sonnet',
          contextWindow: 200000,
          cost: { tiers: [{ inputTokensAbove: 64000 }] },
        },
      }
    );
    assert.equal(modelSetCalls.length, 0);

    // Case C: Active agent tag for 'worker', but model has NO tiers -> NO setModel call
    await registeredHandlers['before_agent_start'](
      { systemPrompt: '<active_agent name="worker"/>\n\nPrompt' },
      {
        model: {
          id: 'claude-3-5-haiku',
          contextWindow: 200000,
        },
      }
    );
    assert.equal(modelSetCalls.length, 0);

    // Case D: Active agent tag for 'worker', model has tiers, but limit >= contextWindow (e.g. window is 64000) -> NO call
    await registeredHandlers['before_agent_start'](
      { systemPrompt: '<active_agent name="worker"/>\n\nPrompt' },
      {
        model: {
          id: 'claude-3-5-sonnet',
          contextWindow: 64000,
          cost: { tiers: [{ inputTokensAbove: 32000 }] },
        },
      }
    );
    assert.equal(modelSetCalls.length, 0);

    // Case E: Active agent tag for 'worker', model has tiers, limit (64000) < contextWindow (200000) -> setModel IS called!
    await registeredHandlers['session_start'](
      { systemPrompt: '<active_agent name="worker"/>\n\nPrompt' },
      {
        model: {
          id: 'claude-3-5-sonnet',
          contextWindow: 200000,
          cost: { tiers: [{ inputTokensAbove: 64000 }] },
        },
      }
    );
    assert.equal(modelSetCalls.length, 1);
    assert.equal(modelSetCalls[0].contextWindow, 64000);
    assert.equal(modelSetCalls[0].id, 'claude-3-5-sonnet');
  } finally {
    if (prevEnv !== undefined) {
      process.env.PI_FRAME_HOME = prevEnv;
    } else {
      delete process.env.PI_FRAME_HOME;
    }
    cleanup();
  }
});

test('ensureSubagentContextLimitExtensionIfReferenced: generates extension if referenced in settings.json and missing', () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-ref-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-ref-piframe-');

  try {
    const extPath = path.join(piframeDir, 'runtime', 'subagent-context-limit.mjs');
    const settingsPath = path.join(agentDir, 'settings.json');
    const originalSettings = {
      subagents: {
        agentOverrides: {
          worker: {
            subagentOnlyExtensions: [extPath],
          },
        },
      },
    };
    fs.writeFileSync(settingsPath, JSON.stringify(originalSettings, null, 2), 'utf8');

    // Extension does not exist initially
    assert.equal(fs.existsSync(extPath), false);

    // Call startup function
    const result = ensureSubagentContextLimitExtensionIfReferenced({ agentDir, piframeDir });
    assert.equal(result, extPath);

    // Extension should now exist with correct source
    assert.equal(fs.existsSync(extPath), true);
    assert.equal(fs.readFileSync(extPath, 'utf8'), generateSubagentContextLimitSource());

    // settings.json must NOT have been modified (read-only check)
    assert.deepEqual(JSON.parse(fs.readFileSync(settingsPath, 'utf8')), originalSettings);
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});

test('ensureSubagentContextLimitExtensionIfReferenced: regenerates extension if outdated', () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-outdated-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-outdated-piframe-');

  try {
    const extPath = path.join(piframeDir, 'runtime', 'subagent-context-limit.mjs');
    const runtimeDir = path.dirname(extPath);
    fs.mkdirSync(runtimeDir, { recursive: true });
    fs.writeFileSync(extPath, '// outdated subagent context limit extension v0.0.1', 'utf8');

    const settingsPath = path.join(agentDir, 'settings.json');
    const originalSettings = {
      subagents: {
        agentOverrides: {
          specialist: {
            subagentOnlyExtensions: [extPath],
          },
        },
      },
    };
    fs.writeFileSync(settingsPath, JSON.stringify(originalSettings), 'utf8');

    const result = ensureSubagentContextLimitExtensionIfReferenced({ agentDir, piframeDir });
    assert.equal(result, extPath);

    // Extension should now have been regenerated with fresh source
    assert.equal(fs.readFileSync(extPath, 'utf8'), generateSubagentContextLimitSource());
    // settings.json must remain unchanged
    assert.deepEqual(JSON.parse(fs.readFileSync(settingsPath, 'utf8')), originalSettings);
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});

test('ensureSubagentContextLimitExtensionIfReferenced: does not generate extension if not referenced', () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-noref-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-noref-piframe-');

  try {
    const extPath = path.join(piframeDir, 'runtime', 'subagent-context-limit.mjs');
    const settingsPath = path.join(agentDir, 'settings.json');
    fs.writeFileSync(
      settingsPath,
      JSON.stringify({
        subagents: {
          agentOverrides: {
            worker: {
              model: 'anthropic/claude-3-5-sonnet',
              subagentOnlyExtensions: ['/some/other/custom-ext.mjs'],
            },
          },
        },
      }),
      'utf8'
    );

    const result = ensureSubagentContextLimitExtensionIfReferenced({ agentDir, piframeDir });
    assert.equal(result, null);
    assert.equal(fs.existsSync(extPath), false);
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});

test('ensureSubagentContextLimitExtensionIfReferenced: handles missing or unparseable settings.json gracefully', () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-invalid-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-invalid-piframe-');

  try {
    // 1. Missing settings.json
    assert.equal(ensureSubagentContextLimitExtensionIfReferenced({ agentDir, piframeDir }), null);

    // 2. Corrupt / invalid JSON
    const settingsPath = path.join(agentDir, 'settings.json');
    fs.writeFileSync(settingsPath, '{ corrupt json ...', 'utf8');
    assert.equal(ensureSubagentContextLimitExtensionIfReferenced({ agentDir, piframeDir }), null);
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});

