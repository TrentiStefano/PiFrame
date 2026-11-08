import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { AgentsService } from '../AgentsService.js';
import type { PiAvailableModel } from '@piframe/pcp-ts';

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

const FAKE_AVAILABLE_MODELS: PiAvailableModel[] = [
  {
    id: 'anthropic/claude-3-5-sonnet',
    name: 'Claude 3.5 Sonnet',
    contextWindow: 200000,
    reasoning: true,
    tiers: [64000, 128000],
  },
  {
    id: 'anthropic/claude-3-5-haiku',
    name: 'Claude 3.5 Haiku',
    contextWindow: 200000,
    reasoning: false,
    tiers: [],
  },
];

test('AgentsService: resolves effective values and origins across override, frontmatter, default, and none', async () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-service-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-service-piframe-');

  try {
    // 1. Setup nicobailon package with 3 agents:
    // - worker: has frontmatter model & thinking
    // - scout: has frontmatter thinking only
    // - researcher: no model or thinking
    const nicoDir = path.join(agentDir, 'npm', 'node_modules', 'pi-subagents');
    const nicoAgentsDir = path.join(nicoDir, 'agents');
    fs.mkdirSync(nicoAgentsDir, { recursive: true });
    fs.writeFileSync(
      path.join(nicoDir, 'package.json'),
      JSON.stringify({ name: 'pi-subagents', version: '1.0.0' })
    );

    fs.writeFileSync(
      path.join(nicoAgentsDir, 'worker.md'),
      `---
name: worker
model: anthropic/claude-3-5-sonnet
thinking: high
---
`
    );

    fs.writeFileSync(
      path.join(nicoAgentsDir, 'scout.md'),
      `---
name: scout
thinking: low
---
`
    );

    fs.writeFileSync(
      path.join(nicoAgentsDir, 'researcher.md'),
      `---
name: researcher
---
`
    );

    // 2. Setup settings.json:
    // - subagents.defaultModel: anthropic/claude-3-5-haiku
    // - subagents.defaultThinking: medium
    // - worker override: model=anthropic/claude-3-5-haiku
    const settingsPath = path.join(agentDir, 'settings.json');
    fs.writeFileSync(
      settingsPath,
      JSON.stringify({
        subagents: {
          defaultModel: 'anthropic/claude-3-5-haiku',
          defaultThinking: 'medium',
          agentOverrides: {
            worker: {
              model: 'anthropic/claude-3-5-haiku',
            },
          },
        },
      })
    );

    const service = new AgentsService({
      agentDir,
      piframeDir,
      getAvailableModels: async () => ({ models: FAKE_AVAILABLE_MODELS }),
    });

    const result = await service.getAgents();
    assert.equal(result.packages.find((p) => p.id === 'pi-subagents')?.installed, true);
    assert.equal(result.availableModels.length, 2);

    const byName = new Map(result.agents.map((a) => [a.name, a]));

    // worker: model from override, thinking from frontmatter
    const worker = byName.get('worker');
    assert.ok(worker);
    assert.equal(worker.model.effective, 'anthropic/claude-3-5-haiku');
    assert.equal(worker.model.origin, 'override');
    assert.equal(worker.model.available, true);
    assert.equal(worker.thinking.effective, 'high');
    assert.equal(worker.thinking.origin, 'frontmatter');

    // scout: model from default, thinking from frontmatter
    const scout = byName.get('scout');
    assert.ok(scout);
    assert.equal(scout.model.effective, 'anthropic/claude-3-5-haiku');
    assert.equal(scout.model.origin, 'default');
    assert.equal(scout.thinking.effective, 'low');
    assert.equal(scout.thinking.origin, 'frontmatter');

    // researcher: model from default, thinking from default
    const researcher = byName.get('researcher');
    assert.ok(researcher);
    assert.equal(researcher.model.effective, 'anthropic/claude-3-5-haiku');
    assert.equal(researcher.model.origin, 'default');
    assert.equal(researcher.thinking.effective, 'medium');
    assert.equal(researcher.thinking.origin, 'default');
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});

test('AgentsService: validates errors (unavailable model, bad thinking, reasoning=false+high, context on no tiers, unknown/readonly agent)', async () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-val-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-val-piframe-');

  try {
    const nicoDir = path.join(agentDir, 'npm', 'node_modules', 'pi-subagents');
    const nicoAgentsDir = path.join(nicoDir, 'agents');
    fs.mkdirSync(nicoAgentsDir, { recursive: true });
    fs.writeFileSync(
      path.join(nicoDir, 'package.json'),
      JSON.stringify({ name: 'pi-subagents', version: '1.0.0' })
    );

    fs.writeFileSync(
      path.join(nicoAgentsDir, 'worker.md'),
      `---
name: worker
model: anthropic/claude-3-5-sonnet
---
`
    );

    fs.writeFileSync(
      path.join(nicoAgentsDir, 'cursor-agent.md'),
      `---
name: cursor-agent
runner:
  type: external-cli
  command: cursor
---
`
    );

    fs.writeFileSync(path.join(agentDir, 'settings.json'), '{}');

    const service = new AgentsService({
      agentDir,
      piframeDir,
      getAvailableModels: async () => ({ models: FAKE_AVAILABLE_MODELS }),
    });

    // 1. Unknown agent
    await assert.rejects(
      async () => {
        await service.updateAgents([
          { kind: 'agent', name: 'nonexistent-agent', model: 'anthropic/claude-3-5-sonnet' },
        ]);
      },
      (err: any) => err?.code === 'AGENTS_VALIDATION_FAILED' && err.details[0].field === 'name'
    );

    // 2. Readonly agent (external CLI)
    await assert.rejects(
      async () => {
        await service.updateAgents([
          { kind: 'agent', name: 'cursor-agent', model: 'anthropic/claude-3-5-sonnet' },
        ]);
      },
      (err: any) => err?.code === 'AGENTS_VALIDATION_FAILED' && err.details[0].field === 'agent'
    );

    // 3. Unavailable model
    await assert.rejects(
      async () => {
        await service.updateAgents([
          { kind: 'agent', name: 'worker', model: 'unknown-provider/fake-model' },
        ]);
      },
      (err: any) => err?.code === 'AGENTS_VALIDATION_FAILED' && err.details[0].field === 'model'
    );

    // 4. Bad thinking level
    await assert.rejects(
      async () => {
        await service.updateAgents([
          { kind: 'agent', name: 'worker', thinking: 'super-high' },
        ]);
      },
      (err: any) => err?.code === 'AGENTS_VALIDATION_FAILED' && err.details[0].field === 'thinking'
    );

    // 5. Reasoning=false model (Haiku) with thinking!=off
    await assert.rejects(
      async () => {
        await service.updateAgents([
          {
            kind: 'agent',
            name: 'worker',
            model: 'anthropic/claude-3-5-haiku',
            thinking: 'high',
          },
        ]);
      },
      (err: any) => err?.code === 'AGENTS_VALIDATION_FAILED' && err.details[0].field === 'thinking'
    );

    // 6. Context limit on model without tiers (Haiku)
    await assert.rejects(
      async () => {
        await service.updateAgents([
          {
            kind: 'agent',
            name: 'worker',
            model: 'anthropic/claude-3-5-haiku',
            thinking: 'off',
            contextLimit: 64000,
          },
        ]);
      },
      (err: any) => err?.code === 'AGENTS_VALIDATION_FAILED' && err.details[0].field === 'contextLimit'
    );

    // 7. Context limit not in options (tiers are [64000, 128000], window 200000; 50000 is invalid)
    await assert.rejects(
      async () => {
        await service.updateAgents([
          {
            kind: 'agent',
            name: 'worker',
            model: 'anthropic/claude-3-5-sonnet',
            contextLimit: 50000,
          },
        ]);
      },
      (err: any) => err?.code === 'AGENTS_VALIDATION_FAILED' && err.details[0].field === 'contextLimit'
    );
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});

test('AgentsService: rejects package modifications when package is not installed', async () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-nopkg-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-nopkg-piframe-');

  try {
    fs.writeFileSync(path.join(agentDir, 'settings.json'), '{}');

    const service = new AgentsService({
      agentDir,
      piframeDir,
      getAvailableModels: async () => ({ models: FAKE_AVAILABLE_MODELS }),
    });

    await assert.rejects(
      async () => {
        await service.updateAgents([
          { kind: 'subagentDefaults', model: 'anthropic/claude-3-5-sonnet' },
        ]);
      },
      (err: any) => err?.code === 'AGENTS_PACKAGE_NOT_INSTALLED'
    );
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});

test('AgentsService: resolves agent aliases from frontmatter and writes under canonical name', async () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-alias-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-alias-piframe-');

  try {
    const nicoDir = path.join(agentDir, 'npm', 'node_modules', 'pi-subagents');
    const nicoAgentsDir = path.join(nicoDir, 'agents');
    fs.mkdirSync(nicoAgentsDir, { recursive: true });
    fs.writeFileSync(
      path.join(nicoDir, 'package.json'),
      JSON.stringify({ name: 'pi-subagents', version: '1.0.0' })
    );

    // oracle has alias advisor
    fs.writeFileSync(
      path.join(nicoAgentsDir, 'oracle.md'),
      `---
name: oracle
description: Strategic oracle advisor
alias: advisor
model: anthropic/claude-3-5-sonnet
---
`
    );

    const settingsPath = path.join(agentDir, 'settings.json');
    fs.writeFileSync(settingsPath, '{}');

    const service = new AgentsService({
      agentDir,
      piframeDir,
      getAvailableModels: async () => ({ models: FAKE_AVAILABLE_MODELS }),
    });

    // 1. Initial get: verify oracle exposes aliases: ['advisor']
    const initial = await service.getAgents();
    const oracleInfo = initial.agents.find((a) => a.name === 'oracle');
    assert.ok(oracleInfo);
    assert.deepEqual(oracleInfo.aliases, ['advisor']);

    // 2. Update using alias name 'advisor'
    const updated = await service.updateAgents([
      {
        kind: 'agent',
        name: 'advisor',
        thinking: 'high',
      },
    ]);

    // Check returned agent result: oracle has thinking.effective === 'high'
    const updatedOracle = updated.agents.find((a) => a.name === 'oracle');
    assert.ok(updatedOracle);
    assert.equal(updatedOracle.thinking.effective, 'high');

    // Check settings.json on disk: must be written under canonical name 'oracle', NOT 'advisor'
    const writtenSettings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    assert.ok(writtenSettings.subagents?.agentOverrides?.oracle);
    assert.equal(writtenSettings.subagents.agentOverrides.oracle.thinking, 'high');
    assert.equal(writtenSettings.subagents.agentOverrides.advisor, undefined);
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});

test('AgentsService: sessionDefaults model must be provider/id format and null removes both provider and model', async () => {
  const { dir: agentDir, cleanup: cleanupAgent } = createTempDir('pi-test-sess-fmt-agent-');
  const { dir: piframeDir, cleanup: cleanupPiframe } = createTempDir('pi-test-sess-fmt-piframe-');

  try {
    const settingsPath = path.join(agentDir, 'settings.json');
    fs.writeFileSync(settingsPath, '{}');

    const service = new AgentsService({
      agentDir,
      piframeDir,
      getAvailableModels: async () => ({ models: FAKE_AVAILABLE_MODELS }),
    });

    // 1. Rejects model without provider (e.g. 'claude-3-5-sonnet')
    await assert.rejects(
      async () => {
        await service.updateAgents([
          {
            kind: 'sessionDefaults',
            model: 'claude-3-5-sonnet',
          },
        ]);
      },
      (err: any) =>
        err?.code === 'AGENTS_VALIDATION_FAILED' &&
        err.details[0].field === 'model' &&
        err.details[0].message.includes('provider/id')
    );

    // 2. Accepts valid provider/id format: sets both defaultProvider and defaultModel
    const result1 = await service.updateAgents([
      {
        kind: 'sessionDefaults',
        model: 'anthropic/claude-3-5-sonnet',
        thinking: 'medium',
      },
    ]);

    assert.equal(result1.sessionDefaults.provider, 'anthropic');
    assert.equal(result1.sessionDefaults.model, 'anthropic/claude-3-5-sonnet');
    assert.equal(result1.sessionDefaults.thinking, 'medium');

    const diskSettings1 = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    assert.equal(diskSettings1.defaultProvider, 'anthropic');
    assert.equal(diskSettings1.defaultModel, 'claude-3-5-sonnet');
    assert.equal(diskSettings1.defaultThinkingLevel, 'medium');

    // 3. Null removes both defaultProvider and defaultModel (and only those)
    const result2 = await service.updateAgents([
      {
        kind: 'sessionDefaults',
        model: null,
      },
    ]);

    assert.equal(result2.sessionDefaults.provider, null);
    assert.equal(result2.sessionDefaults.model, null);
    assert.equal(result2.sessionDefaults.thinking, 'medium'); // Preserved!

    const diskSettings2 = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    assert.equal(diskSettings2.defaultProvider, undefined);
    assert.equal(diskSettings2.defaultModel, undefined);
    assert.equal(diskSettings2.defaultThinkingLevel, 'medium'); // Preserved!
  } finally {
    cleanupAgent();
    cleanupPiframe();
  }
});
