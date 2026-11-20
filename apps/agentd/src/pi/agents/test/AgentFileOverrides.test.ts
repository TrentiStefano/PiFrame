import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { AgentsService, TINTINWEB_CONTEXT_UNSUPPORTED } from '../AgentsService.js';
import {
  ORIGINALS_FILE,
  formatFrontmatterLine,
  getFrontmatterLine,
  setFrontmatterLine
} from '../agentFileOverrides.js';
import type { PiAvailableModel } from '@piframe/pcp-ts';

const MODELS: PiAvailableModel[] = [
  { id: 'github-copilot/gpt-6-luna', name: 'GPT-6 Luna', contextWindow: 400000, reasoning: true, tiers: [272000] },
  { id: 'github-copilot/claude-haiku-5.5', name: 'Claude Haiku 5.5', contextWindow: 200000, reasoning: true, tiers: [] }
];

function tempDir(prefix: string): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

interface Fixture {
  agentDir: string;
  piframeDir: string;
  service: AgentsService;
  reviewerPath: string;
  cleanup: () => void;
}

const REVIEWER =
  '---\r\n' +
  'name: reviewer\r\n' +
  'description: Review specialist\r\n' +
  'tools: read, grep\r\n' +
  'extensions: false\r\n' +
  'model: github-copilot/gpt-6-luna   \r\n' +
  'prompt_mode: append\r\n' +
  '---\r\n' +
  '\r\n' +
  'You are a reviewer.\r\n';

function setup(opts: { tintinweb?: boolean; nicobailon?: boolean; settings?: any } = {}): Fixture {
  const agentDir = tempDir('pi-fm-agent-');
  const piframeDir = tempDir('pi-fm-piframe-');
  if (opts.tintinweb !== false) {
    const dir = path.join(agentDir, 'npm', 'node_modules', '@tintinweb', 'pi-subagents');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      path.join(dir, 'package.json'),
      JSON.stringify({ name: '@tintinweb/pi-subagents', version: '0.26.1' })
    );
  }
  if (opts.nicobailon) {
    const dir = path.join(agentDir, 'npm', 'node_modules', 'pi-subagents');
    fs.mkdirSync(path.join(dir, 'agents'), { recursive: true });
    fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ name: 'pi-subagents', version: '1.0.0' }));
  }
  fs.mkdirSync(path.join(agentDir, 'agents'), { recursive: true });
  const reviewerPath = path.join(agentDir, 'agents', 'reviewer.md');
  fs.writeFileSync(reviewerPath, REVIEWER);
  fs.writeFileSync(path.join(agentDir, 'settings.json'), JSON.stringify(opts.settings ?? { theme: 'dark' }, null, 2));
  const service = new AgentsService({
    agentDir,
    piframeDir,
    getAvailableModels: async () => ({ models: MODELS })
  });
  return {
    agentDir,
    piframeDir,
    service,
    reviewerPath,
    cleanup: () => {
      fs.rmSync(agentDir, { recursive: true, force: true });
      fs.rmSync(piframeDir, { recursive: true, force: true });
    }
  };
}

test('setFrontmatterLine: replaces, inserts and removes one line, keeping CRLF, BOM and every other byte', () => {
  const content = '﻿' + REVIEWER;
  const replaced = setFrontmatterLine(content, 'model', 'model: x/y');
  assert.equal(replaced, content.replace('model: github-copilot/gpt-6-luna   ', 'model: x/y'));

  const inserted = setFrontmatterLine(content, 'thinking', 'thinking: high');
  assert.equal(inserted, content.replace('prompt_mode: append\r\n---', 'prompt_mode: append\r\nthinking: high\r\n---'));
  assert.equal(setFrontmatterLine(inserted, 'thinking', null), content);

  // A key that only appears in the body is not touched.
  const bodyOnly = '---\nname: a\n---\nmodel: in body\n';
  assert.equal(getFrontmatterLine(bodyOnly, 'model'), null);
  assert.equal(setFrontmatterLine(bodyOnly, 'model', 'model: m'), '---\nname: a\nmodel: m\n---\nmodel: in body\n');

  // Nested keys are not top-level matches.
  assert.equal(getFrontmatterLine('---\nrunner:\n  model: z\n---\n', 'model'), null);

  assert.equal(
    formatFrontmatterLine('model', 'github-copilot/claude-haiku-5.5'),
    'model: github-copilot/claude-haiku-5.5'
  );
  assert.equal(formatFrontmatterLine('model', 'has space: yes'), 'model: "has space: yes"');
});

test('tintinweb: a model override is written to the user agent frontmatter, and reset restores the file byte for byte', async () => {
  const f = setup();
  try {
    const before = await f.service.getAgents();
    const reviewer = before.agents.find((a) => a.name === 'reviewer')!;
    assert.equal(reviewer.editable, true);
    assert.equal(reviewer.model.effective, 'github-copilot/gpt-6-luna');
    assert.equal(reviewer.model.origin, 'frontmatter');

    const after = await f.service.updateAgents([
      { kind: 'agent', name: 'reviewer', model: 'github-copilot/claude-haiku-5.5', thinking: 'high' }
    ]);
    const content = fs.readFileSync(f.reviewerPath, 'utf8');
    assert.equal(
      content,
      REVIEWER.replace('model: github-copilot/gpt-6-luna   ', 'model: github-copilot/claude-haiku-5.5').replace(
        'prompt_mode: append\r\n---',
        'prompt_mode: append\r\nthinking: high\r\n---'
      )
    );
    assert.equal(fs.readFileSync(`${f.reviewerPath}.piframe-backup`, 'utf8'), REVIEWER);

    const updated = after.agents.find((a) => a.name === 'reviewer')!;
    assert.equal(updated.model.effective, 'github-copilot/claude-haiku-5.5');
    assert.equal(updated.model.origin, 'override');
    assert.equal(updated.thinking.effective, 'high');
    assert.equal(updated.thinking.origin, 'override');

    // tintinweb never reads settings.json agentOverrides, so nothing is written there.
    const settings = JSON.parse(fs.readFileSync(path.join(f.agentDir, 'settings.json'), 'utf8'));
    assert.deepEqual(settings, { theme: 'dark' });

    // The replaced line is recorded so reset can restore it exactly.
    const originals = JSON.parse(fs.readFileSync(path.join(f.piframeDir, ORIGINALS_FILE), 'utf8'));
    assert.deepEqual(originals[path.resolve(f.reviewerPath)], {
      model: 'model: github-copilot/gpt-6-luna   ',
      thinking: null
    });

    // A second change keeps the first recorded original.
    await f.service.updateAgents([{ kind: 'agent', name: 'reviewer', model: 'github-copilot/gpt-6-luna' }]);
    const originals2 = JSON.parse(fs.readFileSync(path.join(f.piframeDir, ORIGINALS_FILE), 'utf8'));
    assert.equal(originals2[path.resolve(f.reviewerPath)].model, 'model: github-copilot/gpt-6-luna   ');

    const reset = await f.service.updateAgents([{ kind: 'agent', name: 'reviewer', model: null, thinking: null }]);
    assert.equal(fs.readFileSync(f.reviewerPath, 'utf8'), REVIEWER);
    const resetReviewer = reset.agents.find((a) => a.name === 'reviewer')!;
    assert.equal(resetReviewer.model.origin, 'frontmatter');
    assert.equal(resetReviewer.model.effective, 'github-copilot/gpt-6-luna');
    assert.equal(resetReviewer.thinking.origin, 'none');
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.piframeDir, ORIGINALS_FILE), 'utf8')), {});
  } finally {
    f.cleanup();
  }
});

test('tintinweb: stale settings.json overrides are shown as ignored, reset clears them, and context limits are refused', async () => {
  const f = setup({
    settings: {
      theme: 'dark',
      subagents: { agentOverrides: { reviewer: { model: 'github-copilot/claude-haiku-5.5' } } }
    }
  });
  try {
    const state = await f.service.getAgents();
    const reviewer = state.agents.find((a) => a.name === 'reviewer')!;
    // What actually runs is the frontmatter value, not the ignored settings override.
    assert.equal(reviewer.model.effective, 'github-copilot/gpt-6-luna');
    assert.equal(reviewer.model.origin, 'frontmatter');
    assert.ok(state.warnings.some((w) => w.includes('reviewer') && w.includes('ignored')));
    assert.equal(reviewer.context.supported, false);
    assert.equal(reviewer.context.unsupportedReason, TINTINWEB_CONTEXT_UNSUPPORTED);

    await assert.rejects(
      f.service.updateAgents([{ kind: 'agent', name: 'reviewer', contextLimit: 272000 }]),
      (err: any) => err.code === 'AGENTS_VALIDATION_FAILED' && err.details[0].field === 'contextLimit'
    );

    await f.service.updateAgents([{ kind: 'agent', name: 'reviewer', model: null }]);
    assert.equal(fs.readFileSync(f.reviewerPath, 'utf8'), REVIEWER);
    const settings = JSON.parse(fs.readFileSync(path.join(f.agentDir, 'settings.json'), 'utf8'));
    assert.deepEqual(settings, { theme: 'dark', subagents: {} });
  } finally {
    f.cleanup();
  }
});

test('both packages installed: override goes to the agent file and to settings.json agentOverrides', async () => {
  const f = setup({ nicobailon: true });
  try {
    await f.service.updateAgents([{ kind: 'agent', name: 'reviewer', model: 'github-copilot/claude-haiku-5.5' }]);
    assert.equal(
      getFrontmatterLine(fs.readFileSync(f.reviewerPath, 'utf8'), 'model'),
      'model: github-copilot/claude-haiku-5.5'
    );
    const settings = JSON.parse(fs.readFileSync(path.join(f.agentDir, 'settings.json'), 'utf8'));
    assert.equal(settings.subagents.agentOverrides.reviewer.model, 'github-copilot/claude-haiku-5.5');
  } finally {
    f.cleanup();
  }
});

test('nicobailon only: user agent files are never edited; overrides stay in settings.json', async () => {
  const f = setup({ tintinweb: false, nicobailon: true });
  try {
    const state = await f.service.updateAgents([
      { kind: 'agent', name: 'reviewer', model: 'github-copilot/claude-haiku-5.5' }
    ]);
    assert.equal(fs.readFileSync(f.reviewerPath, 'utf8'), REVIEWER);
    assert.equal(fs.existsSync(path.join(f.piframeDir, ORIGINALS_FILE)), false);
    const settings = JSON.parse(fs.readFileSync(path.join(f.agentDir, 'settings.json'), 'utf8'));
    assert.equal(settings.subagents.agentOverrides.reviewer.model, 'github-copilot/claude-haiku-5.5');
    const reviewer = state.agents.find((a) => a.name === 'reviewer')!;
    assert.equal(reviewer.model.origin, 'override');
    assert.equal(reviewer.context.unsupportedReason, null);
  } finally {
    f.cleanup();
  }
});

test('tintinweb: project agents stay read-only and their files are untouched', async () => {
  const f = setup();
  const cwd = tempDir('pi-fm-project-');
  try {
    const projectAgent = path.join(cwd, '.pi', 'agents', 'planner.md');
    fs.mkdirSync(path.dirname(projectAgent), { recursive: true });
    fs.writeFileSync(projectAgent, '---\nname: planner\nmodel: github-copilot/gpt-6-luna\n---\n');
    const state = await f.service.getAgents(cwd);
    const planner = state.agents.find((a) => a.name === 'planner')!;
    assert.equal(planner.editable, false);
    await assert.rejects(
      f.service.updateAgents([{ kind: 'agent', name: 'planner', model: 'github-copilot/claude-haiku-5.5' }], cwd),
      (err: any) => err.code === 'AGENTS_VALIDATION_FAILED'
    );
    assert.equal(fs.readFileSync(projectAgent, 'utf8'), '---\nname: planner\nmodel: github-copilot/gpt-6-luna\n---\n');
  } finally {
    fs.rmSync(cwd, { recursive: true, force: true });
    f.cleanup();
  }
});
