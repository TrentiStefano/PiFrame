import test from 'node:test';
import assert from 'node:assert/strict';
import { approvalStatus } from '../src/index.mjs';

const baseline = (asAny) => ({ agentd: { lib: { 'as any': asAny, ': any': 165 }, test: { 'as any': 158 } } });

test('nothing to approve: not needed and no comment', () => {
  const result = approvalStatus({
    baseBaseline: baseline(40),
    headBaseline: baseline(40),
    changedPaths: ['apps/agentd/src/server.ts', 'README.md'],
    labelEvents: [],
    latestPushAt: '2026-11-20T10:00:00Z'
  });
  assert.equal(result.status, 'not-needed');
  assert.deepEqual(result.reasons, []);
  assert.equal(result.comment, null);
});

test('a raised baseline number needs approval, and the comment names the count', () => {
  const result = approvalStatus({
    baseBaseline: baseline(40),
    headBaseline: baseline(41),
    changedPaths: ['tools/guardrails/escape-hatch-baseline.json', 'apps/agentd/src/server.ts'],
    labelEvents: [],
    latestPushAt: '2026-11-20T10:00:00Z'
  });
  assert.equal(result.status, 'needed');
  assert.deepEqual(result.reasons, ['agentd lib `as any` 40 → 41']);
  assert.match(result.comment, /agentd lib `as any` 40 → 41/);
  assert.match(result.comment, /human-approved/);
  assert.match(result.comment, /<!-- guardrails-approval -->/);
});

test('a lowered baseline number alone needs no approval and no comment', () => {
  const result = approvalStatus({
    baseBaseline: baseline(40),
    headBaseline: baseline(39),
    changedPaths: ['tools/guardrails/escape-hatch-baseline.json', 'apps/agentd/src/server.ts'],
    labelEvents: [],
    latestPushAt: '2026-11-20T10:00:00Z'
  });
  assert.equal(result.status, 'not-needed');
  assert.deepEqual(result.reasons, []);
  assert.equal(result.comment, null);
});

test('a change to a guarded path needs approval, whichever way it goes', () => {
  const guarded = [
    'apps/pi_frame/analysis_options.yaml',
    'tsconfig.base.json',
    'apps/agentd/tsconfig.build.json',
    '.prettierrc.json',
    '.prettierignore',
    'apps/agentd/eslint.config.mjs',
    '.eslintrc.json',
    'tools/guardrails/src/escape-hatches.mjs',
    'tools/scripts/format.mjs',
    'tools/scripts/flutter-projects.json',
    'tools/scripts/audit-escape-hatches.mjs',
    'tools/scripts/guardrails-approval.mjs',
    '.github/workflows/ci.yml',
    '.claude/settings.json',
    '.claude/hooks/guard-command.mjs',
    '.pi/extensions/guard-command.ts',
    '.codex/rules/guard.rules'
  ];
  for (const path of guarded) {
    const result = approvalStatus({
      baseBaseline: baseline(40),
      headBaseline: baseline(40),
      changedPaths: ['apps/agentd/src/server.ts', path],
      labelEvents: [],
      latestPushAt: '2026-11-20T10:00:00Z'
    });
    assert.equal(result.status, 'needed', `expected ${path} to need approval`);
    assert.equal(result.reasons.length, 1, `one reason for ${path}`);
    assert.match(result.reasons[0], new RegExp(`\`${path.replaceAll('.', '\\.')}\``));
    assert.ok(result.comment.includes(result.reasons[0]));
  }
});

const needsApproval = (labelEvents, latestPushAt = '2026-11-20T10:00:00Z') =>
  approvalStatus({
    baseBaseline: baseline(40),
    headBaseline: baseline(41),
    changedPaths: ['tools/guardrails/escape-hatch-baseline.json', '.github/workflows/ci.yml'],
    labelEvents,
    latestPushAt
  });

test('a label added after the latest push approves, and the comment still lists every reason', () => {
  const result = needsApproval([
    { action: 'labeled', label: 'ready-for-agent', at: '2026-11-20T09:00:00Z', actor: 'bot' },
    { action: 'labeled', label: 'human-approved', at: '2026-11-20T10:05:00Z', actor: 'maintainer' }
  ]);
  assert.equal(result.status, 'approved');
  assert.equal(result.stale, false);
  assert.deepEqual(result.reasons, ['agentd lib `as any` 40 → 41', 'CI workflow changed: `.github/workflows/ci.yml`']);
  assert.match(result.comment, /approved by @maintainer/i);
  assert.ok(result.reasons.every((r) => result.comment.includes(r)));
});

test('a label added before the latest push is stale, and the comment says so', () => {
  const result = needsApproval([{ action: 'labeled', label: 'human-approved', at: '2026-11-20T09:59:00Z' }]);
  assert.equal(result.status, 'needed');
  assert.equal(result.stale, true);
  assert.match(result.comment, /stale/i);
  assert.match(result.comment, /2026-11-20T09:59:00Z/);
});

test('a label that was removed again does not approve', () => {
  const result = needsApproval([
    { action: 'labeled', label: 'human-approved', at: '2026-11-20T10:05:00Z' },
    { action: 'unlabeled', label: 'human-approved', at: '2026-11-20T10:06:00Z' }
  ]);
  assert.equal(result.status, 'needed');
  assert.equal(result.stale, false);
  assert.doesNotMatch(result.comment, /stale/i);
});

test('without a known push time an existing label counts as stale', () => {
  const result = needsApproval([{ action: 'labeled', label: 'human-approved', at: '2026-11-20T10:05:00Z' }], null);
  assert.equal(result.status, 'needed');
  assert.equal(result.stale, true);
});

test('ordinary paths that only look like guarded ones need no approval', () => {
  const result = approvalStatus({
    baseBaseline: baseline(40),
    headBaseline: baseline(40),
    changedPaths: [
      'tools/scripts/check-version-sync.mjs',
      'docs/guardrails.md',
      '.claude/skills/tdd/SKILL.md',
      'apps/pi_frame/lib/analysis_options_view.dart'
    ],
    labelEvents: [],
    latestPushAt: '2026-11-20T10:00:00Z'
  });
  assert.equal(result.status, 'not-needed');
});
