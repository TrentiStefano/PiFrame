import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { filterModelsByEnabledPatterns, readEnabledModelPatterns } from '../modelScope.js';

const models = [
  { provider: 'github-copilot', id: 'gpt-6-luna', name: 'GPT 6 Luna' },
  { provider: 'github-copilot', id: 'claude-sonnet-4', name: 'Claude Sonnet 4' },
  { provider: 'openai', id: 'gpt-4.1', name: 'GPT 4.1' },
];

test('empty Pi enabledModels scope preserves Pi-authenticated models', () => {
  assert.deepEqual(filterModelsByEnabledPatterns(models, []), models);
});

test('enabledModels scope supports exact, provider glob and fuzzy model names', () => {
  assert.deepEqual(
    filterModelsByEnabledPatterns(models, ['github-copilot/gpt-6-luna', 'claude-sonnet']),
    models.slice(0, 2),
  );
  assert.deepEqual(filterModelsByEnabledPatterns(models, ['openai/gpt-*']), [models[2]]);
  assert.deepEqual(filterModelsByEnabledPatterns(models, ['not-enabled']), []);
});

test('reads Pi enabledModels from configured agent directory only', () => {
  const agentDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-model-scope-'));
  try {
    fs.writeFileSync(path.join(agentDir, 'settings.json'), JSON.stringify({ enabledModels: ['github-copilot/gpt-*'] }));
    assert.deepEqual(readEnabledModelPatterns(agentDir), ['github-copilot/gpt-*']);
  } finally {
    fs.rmSync(agentDir, { recursive: true, force: true });
  }
});
