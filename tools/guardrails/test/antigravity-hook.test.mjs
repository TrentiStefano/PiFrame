import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// The Antigravity agent guard: .agents/hooks.json runs .agents/hooks/guard-command.mjs before every run_command.
const hooksDir = fileURLToPath(new URL('../../../.agents/', import.meta.url));
const script = fileURLToPath(new URL('../../../.agents/hooks/guard-command.mjs', import.meta.url));

const runHook = (commandLine) => {
  const payload = {
    conversationId: 'test',
    hookEventName: 'PreToolUse',
    cwd: hooksDir,
    toolCall: { id: 'toolu_01', name: 'run_command', args: { CommandLine: commandLine } },
    stepIdx: 1
  };
  const result = spawnSync(process.execPath, [script], { input: JSON.stringify(payload), encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
};

test('denies a command that applies the approval label, with the guard reason', () => {
  const output = runHook(['gh pr edit 1 --add-label', 'human-approved'].join(' '));
  assert.equal(output.decision, 'deny');
  assert.match(output.reason, /\S/);
});

test('denies editing labels', () => {
  assert.equal(runHook('gh label delete wip --yes').decision, 'deny');
});

test('leaves an allowed command to the normal permissions', () => {
  // No decision: Antigravity applies the user's own permission settings.
  assert.deepEqual(runHook('gh pr view 1'), {});
});

test('hooks.json runs the script before every run_command', () => {
  const hooks = JSON.parse(readFileSync(`${hooksDir}hooks.json`, 'utf8'));
  const groups = Object.values(hooks).flatMap((hook) => hook.PreToolUse ?? []);
  const group = groups.find((entry) => entry.matcher === 'run_command');
  assert.ok(group, 'a PreToolUse group matches run_command');
  assert.ok(group.hooks.some((handler) => handler.command.includes('hooks/guard-command.mjs')));
});
