import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { inputTierThresholds, modelName } from '../Dispatcher.js';

test('a model name falls back to its id and is never the string "undefined"', () => {
  assert.equal(modelName({ id: 'gpt-x', name: 'GPT X' }), 'GPT X');
  assert.equal(modelName({ id: 'gpt-x' }), 'gpt-x');
  assert.equal(modelName({}), '');
});

test('input tier thresholds keep only finite numbers, sorted ascending', () => {
  assert.deepEqual(
    inputTierThresholds({ tiers: [{ inputTokensAbove: 200000 }, { inputTokensAbove: 'x' }, { inputTokensAbove: 1000 }] }),
    [1000, 200000]
  );
  assert.deepEqual(inputTierThresholds(undefined), []);
  assert.deepEqual(inputTierThresholds({ tiers: 'not a list' }), []);
});
