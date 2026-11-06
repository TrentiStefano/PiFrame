import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import {
  detectSubagentPackages,
  discoverAgents,
  displayPath,
} from '../agentDiscovery.js';

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

test('displayPath: replaces home directory with ~', () => {
  const home = os.homedir();
  const filePath = path.join(home, '.pi', 'agent', 'settings.json');
  assert.equal(displayPath(filePath), '~/.pi/agent/settings.json');
});

test('detectSubagentPackages: detects installed nicobailon and tintinweb packages', () => {
  const { dir: tempAgentDir, cleanup } = createTempDir('pi-test-agent-dir-');
  try {
    // 1. Initially neither installed
    const res1 = detectSubagentPackages(tempAgentDir, {});
    assert.equal(res1.packages.length, 2);
    assert.equal(res1.packages[0].id, 'pi-subagents');
    assert.equal(res1.packages[0].installed, false);
    assert.equal(res1.packages[0].version, null);
    assert.equal(res1.packages[1].id, '@tintinweb/pi-subagents');
    assert.equal(res1.packages[1].installed, false);

    // 2. Install fake nicobailon package
    const nicoDir = path.join(tempAgentDir, 'npm', 'node_modules', 'pi-subagents');
    fs.mkdirSync(nicoDir, { recursive: true });
    fs.writeFileSync(
      path.join(nicoDir, 'package.json'),
      JSON.stringify({ name: 'pi-subagents', version: '0.9.5' })
    );

    const res2 = detectSubagentPackages(tempAgentDir, {});
    const nicoPkg = res2.packages.find((p) => p.id === 'pi-subagents');
    assert.ok(nicoPkg);
    assert.equal(nicoPkg.installed, true);
    assert.equal(nicoPkg.version, '0.9.5');
    assert.equal(res2.nicobailonDir, nicoDir);

    // 3. Install fake tintinweb package
    const tintinDir = path.join(
      tempAgentDir,
      'npm',
      'node_modules',
      '@tintinweb',
      'pi-subagents'
    );
    fs.mkdirSync(tintinDir, { recursive: true });
    fs.writeFileSync(
      path.join(tintinDir, 'package.json'),
      JSON.stringify({ name: '@tintinweb/pi-subagents', version: '1.2.0' })
    );

    const res3 = detectSubagentPackages(tempAgentDir, {});
    const tintinPkg = res3.packages.find((p) => p.id === '@tintinweb/pi-subagents');
    assert.ok(tintinPkg);
    assert.equal(tintinPkg.installed, true);
    assert.equal(tintinPkg.version, '1.2.0');
    assert.equal(res3.tintinwebDir, tintinDir);
  } finally {
    cleanup();
  }
});

test('discoverAgents: discovers nicobailon agents with external CLI profile and tintinweb agents', () => {
  const { dir: tempAgentDir, cleanup: cleanupAgent } = createTempDir('pi-test-agents-');
  const { dir: tempProjectDir, cleanup: cleanupProject } = createTempDir('pi-test-proj-');

  try {
    // 1. Setup nicobailon fixture directory with 3 agents: worker (builtin), custom (package), cursor (external-cli)
    const nicoDir = path.join(tempAgentDir, 'npm', 'node_modules', 'pi-subagents');
    const nicoAgentsDir = path.join(nicoDir, 'agents');
    fs.mkdirSync(nicoAgentsDir, { recursive: true });
    fs.writeFileSync(
      path.join(nicoDir, 'package.json'),
      JSON.stringify({ name: 'pi-subagents', version: '0.9.5' })
    );

    // worker.md (builtin)
    fs.writeFileSync(
      path.join(nicoAgentsDir, 'worker.md'),
      `---
name: worker
description: Worker implementation agent
model: anthropic/claude-3-5-sonnet
thinking: high
---
Worker body.
`
    );

    // custom-helper.md (package non-builtin)
    fs.writeFileSync(
      path.join(nicoAgentsDir, 'custom-helper.md'),
      `---
name: custom-helper
description: Custom package agent
---
Custom helper body.
`
    );

    // cursor-agent.md (external-cli runner)
    fs.writeFileSync(
      path.join(nicoAgentsDir, 'cursor-agent.md'),
      `---
name: cursor-agent
description: External cursor runner
runner:
  type: external-cli
  command: cursor
---
Cursor agent body.
`
    );

    // 2. Setup user agent: my-agent.md and a user worker override
    const userAgentsDir = path.join(tempAgentDir, 'agents');
    fs.mkdirSync(userAgentsDir, { recursive: true });
    fs.writeFileSync(
      path.join(userAgentsDir, 'my-agent.md'),
      `---
name: my-agent
description: My user agent
---
`
    );

    // 3. Setup project agent: proj-agent.md
    const projAgentsDir = path.join(tempProjectDir, '.pi', 'agents');
    fs.mkdirSync(projAgentsDir, { recursive: true });
    fs.writeFileSync(
      path.join(projAgentsDir, 'proj-agent.md'),
      `---
name: proj-agent
description: Project agent
---
`
    );

    const pkgs = detectSubagentPackages(tempAgentDir, {});
    const agents = discoverAgents(tempAgentDir, pkgs, tempProjectDir);

    const byName = new Map(agents.map((a) => [a.name, a]));

    // worker: builtin, editable
    const worker = byName.get('worker');
    assert.ok(worker);
    assert.equal(worker.source, 'builtin');
    assert.equal(worker.editable, true);
    assert.equal(worker.readOnlyReason, null);
    assert.equal(worker.frontmatterModel, 'anthropic/claude-3-5-sonnet');
    assert.equal(worker.frontmatterThinking, 'high');

    // custom-helper: package, editable
    const custom = byName.get('custom-helper');
    assert.ok(custom);
    assert.equal(custom.source, 'package');
    assert.equal(custom.editable, true);

    // cursor-agent: external-cli, NOT editable
    const cursor = byName.get('cursor-agent');
    assert.ok(cursor);
    assert.equal(cursor.editable, false);
    assert.equal(cursor.readOnlyReason, 'external CLI runner');

    // my-agent: user, editable
    const myAgent = byName.get('my-agent');
    assert.ok(myAgent);
    assert.equal(myAgent.source, 'user');
    assert.equal(myAgent.editable, true);

    // proj-agent: project, read-only
    const projAgent = byName.get('proj-agent');
    assert.ok(projAgent);
    assert.equal(projAgent.source, 'project');
    assert.equal(projAgent.editable, false);
    assert.equal(projAgent.readOnlyReason, 'project agent (read-only)');
  } finally {
    cleanupAgent();
    cleanupProject();
  }
});

test('discoverAgents: user agent shadows builtin package agent', () => {
  const { dir: tempAgentDir, cleanup } = createTempDir('pi-test-shadow-');
  try {
    const nicoDir = path.join(tempAgentDir, 'npm', 'node_modules', 'pi-subagents');
    const nicoAgentsDir = path.join(nicoDir, 'agents');
    fs.mkdirSync(nicoAgentsDir, { recursive: true });
    fs.writeFileSync(
      path.join(nicoDir, 'package.json'),
      JSON.stringify({ name: 'pi-subagents', version: '0.9.5' })
    );

    fs.writeFileSync(
      path.join(nicoAgentsDir, 'worker.md'),
      `---
name: worker
description: Builtin worker
---
`
    );

    // User agent shadows worker and defines alias
    const userAgentsDir = path.join(tempAgentDir, 'agents');
    fs.mkdirSync(userAgentsDir, { recursive: true });
    fs.writeFileSync(
      path.join(userAgentsDir, 'worker.md'),
      `---
name: worker
description: User worker override
alias: worker-bee
---
`
    );

    const pkgs = detectSubagentPackages(tempAgentDir, {});
    const agents = discoverAgents(tempAgentDir, pkgs);

    const worker = agents.find((a) => a.name === 'worker');
    assert.ok(worker);
    assert.equal(worker.source, 'user');
    assert.equal(worker.description, 'User worker override');
    assert.deepEqual(worker.aliases, ['worker-bee']);
  } finally {
    cleanup();
  }
});

test('discoverAgents: extracts aliases from alias and aliases frontmatter', () => {
  const { dir: tempAgentDir, cleanup } = createTempDir('pi-test-aliases-');
  try {
    const agentsDir = path.join(tempAgentDir, 'agents');
    fs.mkdirSync(agentsDir, { recursive: true });

    // 1. Single alias
    fs.writeFileSync(
      path.join(agentsDir, 'oracle.md'),
      `---
name: oracle
alias: advisor
---
`
    );

    // 2. Multiple aliases in inline array
    fs.writeFileSync(
      path.join(agentsDir, 'researcher.md'),
      `---
name: researcher
aliases: [investigator, scout-plus]
---
`
    );

    const pkgs = detectSubagentPackages(tempAgentDir, {});
    const agents = discoverAgents(tempAgentDir, pkgs);

    const oracle = agents.find((a) => a.name === 'oracle');
    assert.ok(oracle);
    assert.deepEqual(oracle.aliases, ['advisor']);

    const researcher = agents.find((a) => a.name === 'researcher');
    assert.ok(researcher);
    assert.deepEqual(researcher.aliases, ['investigator', 'scout-plus']);
  } finally {
    cleanup();
  }
});
