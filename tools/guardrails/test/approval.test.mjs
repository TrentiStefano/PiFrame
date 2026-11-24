import test from 'node:test';
import assert from 'node:assert/strict';
import { approvalStatus, stepList } from '../src/index.mjs';

const baseline = (asAny) => ({ agentd: { lib: { 'as any': asAny, ': any': 165 }, test: { 'as any': 158 } } });

test('nothing to approve: not needed and no comment', () => {
  const result = approvalStatus({
    baseBaseline: baseline(40),
    headBaseline: baseline(40),
    changedPaths: ['apps/agentd/src/server.ts', 'README.md'],
    labelEvents: [],
    ciRunTimes: ['2026-11-20T10:00:00Z']
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
    ciRunTimes: ['2026-11-20T10:00:00Z']
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
    ciRunTimes: ['2026-11-20T10:00:00Z']
  });
  assert.equal(result.status, 'not-needed');
  assert.deepEqual(result.reasons, []);
  assert.equal(result.comment, null);
});

test('a change to a guarded path needs approval, whichever way it goes', () => {
  const guarded = [
    'apps/pi_frame/analysis_options.yaml',
    'tsconfig.base.json',
    'apps/agentd/tsconfig.json',
    '.prettierrc.json',
    '.prettierignore',
    'apps/agentd/eslint.config.mjs',
    '.eslintrc.json',
    'tools/guardrails/src/escape-hatches.mjs',
    'tools/guardrails/src/agent-map.mjs',
    'tools/scripts/check-agent-map.mjs',
    'tools/guardrails/src/boundary.mjs',
    'tools/guardrails/boundary.json',
    'tools/scripts/check-boundaries.mjs',
    'tools/guardrails/src/timers.mjs',
    'tools/scripts/check-timers.mjs',
    'AGENTS.md',
    'tools/scripts/format.mjs',
    'tools/scripts/flutter-projects.json',
    'tools/scripts/typescript-projects.json',
    'tsconfig.base.json',
    'apps/agentd/tsconfig.json',
    'eslint.config.mjs',
    'tools/scripts/audit-escape-hatches.mjs',
    'tools/scripts/check-doc-links.mjs',
    'tools/guardrails/src/doc-links.mjs',
    'tools/scripts/guardrails-approval.mjs',
    '.github/workflows/ci.yml',
    '.claude/settings.json',
    '.claude/hooks/guard-command.mjs',
    '.pi/extensions/guard-command.ts',
    '.codex/rules/guard.rules',
    'tools/scripts/lint-flutter.mjs',
    'tools/scripts/test-flutter.js',
    'tools/scripts/setup-flutter.js',
    'tools/scripts/check-version-sync.mjs',
    'tools/scripts/sync-changelog.mjs',
    'tools/scripts/verify-ci.mjs',
    'tools/scripts/check.mjs',
    'tools/codegen/generate.js',
    'tools/codegen/templates/dart.mjs',
    'package.json',
    'apps/agentd/package.json',
    'tools/guardrails/package.json',
    'test/e2e/package.json',
    'pnpm-workspace.yaml',
    'DESIGN.md',
    'tools/scripts/lint-design.mjs',
    'tools/scripts/check-design-tokens.mjs',
    'tools/scripts/repo-files.mjs'
  ];
  for (const path of guarded) {
    const result = approvalStatus({
      baseBaseline: baseline(40),
      headBaseline: baseline(40),
      changedPaths: ['apps/agentd/src/server.ts', path],
      labelEvents: [],
      ciRunTimes: ['2026-11-20T10:00:00Z']
    });
    assert.equal(result.status, 'needed', `expected ${path} to need approval`);
    assert.equal(result.reasons.length, 1, `one reason for ${path}`);
    assert.match(result.reasons[0], new RegExp(`\`${path.replaceAll('.', '\\.')}\``));
    assert.ok(result.comment.includes(result.reasons[0]));
  }
});

const needsApproval = (labelEvents, push = { ciRunTimes: ['2026-11-20T10:00:00Z'] }) =>
  approvalStatus({
    baseBaseline: baseline(40),
    headBaseline: baseline(41),
    changedPaths: ['tools/guardrails/escape-hatch-baseline.json', '.github/workflows/ci.yml'],
    labelEvents,
    ...push
  });

const APPROVED_AT_0930 = [{ action: 'labeled', label: 'human-approved', at: '2026-11-20T09:30:00Z' }];

test('the latest push is the newest ci.yml run for the head commit, whatever order GitHub lists them in', () => {
  const result = needsApproval(APPROVED_AT_0930, {
    ciRunTimes: ['2026-11-20T09:00:00Z', '2026-11-20T10:00:00Z', '2026-11-20T08:00:00Z']
  });
  assert.equal(result.latestPushAt, '2026-11-20T10:00:00Z');
  assert.equal(result.stale, true);
});

test('a run triggered by a push counts as the latest push', () => {
  for (const eventAction of ['opened', 'synchronize', 'reopened']) {
    const result = needsApproval(APPROVED_AT_0930, {
      eventAction,
      runCreatedAt: '2026-11-20T10:00:00Z',
      ciRunTimes: ['2026-11-20T09:00:00Z']
    });
    assert.equal(result.latestPushAt, '2026-11-20T10:00:00Z', eventAction);
    assert.equal(result.status, 'needed', eventAction);
    assert.equal(result.stale, true, eventAction);
  }
});

test('a run triggered by a label change is not a push, so its own time does not make the label stale', () => {
  const result = needsApproval(APPROVED_AT_0930, {
    eventAction: 'labeled',
    runCreatedAt: '2026-11-20T09:31:00Z',
    ciRunTimes: ['2026-11-20T09:00:00Z']
  });
  assert.equal(result.latestPushAt, '2026-11-20T09:00:00Z');
  assert.equal(result.status, 'approved');
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
  const result = needsApproval([{ action: 'labeled', label: 'human-approved', at: '2026-11-20T10:05:00Z' }], {
    eventAction: 'labeled',
    runCreatedAt: '2026-11-20T10:06:00Z',
    ciRunTimes: []
  });
  assert.equal(result.latestPushAt, null);
  assert.equal(result.status, 'needed');
  assert.equal(result.stale, true);
  assert.match(result.comment, /time unknown/);
});

const notNeeded = (previousComment) =>
  approvalStatus({
    baseBaseline: baseline(40),
    headBaseline: baseline(40),
    changedPaths: ['apps/agentd/src/server.ts'],
    ciRunTimes: ['2026-11-20T10:00:00Z'],
    previousComment
  });

test('a PR that no longer needs approval updates its earlier comment to say so', () => {
  const earlier = needsApproval([]).comment;
  const result = notNeeded(earlier);
  assert.equal(result.status, 'not-needed');
  assert.match(result.comment, /^<!-- guardrails-approval -->/);
  assert.match(result.comment, /not needed/i);
  assert.match(result.comment, /changes a guardrail/);
  assert.doesNotMatch(result.comment, /loosen/);
});

test('a PR that never needed approval gets no comment', () => {
  assert.equal(notNeeded(null).comment, null);
  assert.equal(notNeeded(undefined).comment, null);
});

test('ordinary paths that only look like guarded ones need no approval', () => {
  const result = approvalStatus({
    baseBaseline: baseline(40),
    headBaseline: baseline(40),
    changedPaths: [
      'tools/scripts/smoke-real-pi.mjs',
      'docs/guardrails.md',
      'apps/pi_frame/AGENTS.md',
      'apps/agentd/node_modules/foo/package.json',
      '.claude/skills/tdd/SKILL.md',
      'apps/pi_frame/lib/analysis_options_view.dart',
      'docs/design/screens/chat-dark.png'
    ],
    labelEvents: [],
    ciRunTimes: ['2026-11-20T10:00:00Z']
  });
  assert.equal(result.status, 'not-needed');
});

// Every script file a gate step runs, from an independent reading of the step list: a command argument that is a
// repository path to a JavaScript or TypeScript file.
function scriptsRunByTheGate() {
  const all = [
    ...stepList('verify', { release: true, e2e: true, platform: 'linux', appVersion: '1.0.0' }),
    ...stepList('ci'),
    ...stepList('check')
  ];
  const scripts = new Set();
  for (const { command, cwd } of all) {
    for (const arg of command) {
      if (/^[\w./-]+\.(mjs|cjs|js|ts)$/.test(arg)) scripts.add(cwd ? `${cwd}/${arg}` : arg);
    }
  }
  return [...scripts];
}

test('every script a gate step runs is guarded, so making it exit 0 needs approval', () => {
  const scripts = scriptsRunByTheGate();
  assert.ok(scripts.includes('tools/scripts/lint-flutter.mjs'), scripts.join(', '));
  assert.ok(scripts.includes('tools/recon/verify.ts'), scripts.join(', '));
  for (const path of scripts) {
    const result = approvalStatus({
      baseBaseline: baseline(40),
      headBaseline: baseline(40),
      changedPaths: [path],
      labelEvents: [],
      ciRunTimes: ['2026-11-20T10:00:00Z']
    });
    assert.equal(result.status, 'needed', `expected ${path} to need approval`);
  }
});

const diagnosticsBaseline = (count) => ({ 'dart-analyze': { 'apps/pi_frame': { avoid_print: count } } });

test('a raised diagnostics count needs approval; a lowered one, or the baseline file itself, does not', () => {
  const input = {
    baseBaseline: baseline(40),
    headBaseline: baseline(40),
    labelEvents: [],
    ciRunTimes: ['2026-11-20T10:00:00Z'],
    changedPaths: ['tools/guardrails/diagnostics-baseline.json']
  };
  const raised = approvalStatus({
    ...input,
    diagnosticsBaseBaseline: diagnosticsBaseline(1),
    diagnosticsHeadBaseline: diagnosticsBaseline(2)
  });
  assert.equal(raised.status, 'needed');
  assert.deepEqual(raised.reasons, ['dart-analyze apps/pi_frame `avoid_print` 1 → 2']);
  assert.match(raised.comment, /human-approved/);

  const lowered = approvalStatus({
    ...input,
    diagnosticsBaseBaseline: diagnosticsBaseline(2),
    diagnosticsHeadBaseline: diagnosticsBaseline(1)
  });
  assert.equal(lowered.status, 'not-needed');
  assert.deepEqual(lowered.reasons, []);
});
