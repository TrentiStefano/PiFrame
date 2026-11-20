/**
 * Approval status: decides whether a pull request loosens a guardrail and, if so, whether a human approved it.
 *
 * A PR needs approval when it raises a number in the escape-hatch baseline (lowering is free) or changes a guarded
 * path (analyzer options, tsconfig, formatter/linter configs, guardrail tooling, workflows, the agent guards). It is
 * approved only when the `human-approved` label is on the PR and was added after the latest push: an older label
 * is stale, because the human has not seen the newer commits.
 *
 * Pure: no I/O. tools/scripts/guardrails-approval.mjs (run by .github/workflows/guardrails-approval.yml) reads git
 * and GitHub and calls it. See docs/pr-verification.md.
 */
import { BASELINE_PATH } from './escape-hatches.mjs';

export const APPROVAL_LABEL = 'human-approved';
/** Hidden marker that identifies the job's one comment, so it is updated instead of duplicated. */
export const APPROVAL_MARKER = '<!-- guardrails-approval -->';

const BASENAME = (path) => path.slice(path.lastIndexOf('/') + 1);

/** Guarded single files that are not caught by a name or folder rule below. */
const TOOLING_FILES = new Set([
  'tools/scripts/format.mjs',
  'tools/scripts/flutter-projects.json',
  'tools/scripts/audit-escape-hatches.mjs',
  'tools/scripts/guardrails-approval.mjs'
]);
const AGENT_GUARD_FILES = new Set(['.claude/settings.json']);
const AGENT_GUARD_DIRS = ['.claude/hooks/', '.pi/extensions/', '.codex/rules/'];

/** Why a path is guarded, or undefined when changing it needs no approval. */
function guardedKind(path) {
  if (path === BASELINE_PATH) return undefined; // only its increases need approval, see baselineIncreases
  const name = BASENAME(path);
  if (name === 'analysis_options.yaml') return 'Dart analyzer options';
  if (/^tsconfig.*\.json$/.test(name)) return 'TypeScript config';
  if (name === '.prettierrc.json' || name === '.prettierignore') return 'formatter config';
  if (/^(\.eslintrc(\..+)?|\.eslintignore|eslint\.config\.[cm]?[jt]s)$/.test(name)) return 'linter config';
  if (path.startsWith('.github/workflows/')) return 'CI workflow';
  if (path.startsWith('tools/guardrails/') || TOOLING_FILES.has(path)) return 'guardrail tooling';
  if (AGENT_GUARD_FILES.has(path) || AGENT_GUARD_DIRS.some((dir) => path.startsWith(dir))) return 'agent guard';
  return undefined;
}

function guardedChanges(changedPaths) {
  const paths = [...new Set(changedPaths.map((p) => p.replaceAll('\\', '/')))].sort();
  return paths.flatMap((path) => {
    const kind = guardedKind(path);
    return kind ? [`${kind} changed: \`${path}\``] : [];
  });
}

/** Every baseline count that is higher on the head than on the base (a new entry counts from 0). */
function baselineIncreases(base, head) {
  const out = [];
  for (const [pkg, kinds] of Object.entries(head ?? {})) {
    for (const [kind, patterns] of Object.entries(kinds ?? {})) {
      for (const [pattern, count] of Object.entries(patterns ?? {})) {
        const before = base?.[pkg]?.[kind]?.[pattern] ?? 0;
        if (typeof count === 'number' && count > before) out.push(`${pkg} ${kind} \`${pattern}\` ${before} → ${count}`);
      }
    }
  }
  return out;
}

/** The label's latest `labeled` event if it is still on the PR, else undefined. */
function currentLabel(labelEvents) {
  let current;
  for (const event of [...labelEvents].sort((a, b) => Date.parse(a.at) - Date.parse(b.at))) {
    if (event.label?.toLowerCase() !== APPROVAL_LABEL) continue;
    current = event.action === 'labeled' ? event : undefined;
  }
  return current;
}

/**
 * @param {object} input
 * @param {object} input.baseBaseline escape-hatch baseline on the PR's base
 * @param {object} input.headBaseline escape-hatch baseline on the PR's head
 * @param {string[]} input.changedPaths paths the PR changes (renames as both old and new path)
 * @param {{ action: 'labeled' | 'unlabeled', label: string, at: string, actor?: string }[]} input.labelEvents the
 *   PR's label events, with the time GitHub recorded them (ISO 8601)
 * @param {string | null} input.latestPushAt when GitHub recorded the latest push to the PR (ISO 8601); null when
 *   unknown, which makes any label stale
 * @returns {{ status: 'not-needed' | 'needed' | 'approved', reasons: string[], stale: boolean, comment: string | null }}
 */
export function approvalStatus({ baseBaseline, headBaseline, changedPaths = [], labelEvents = [], latestPushAt }) {
  const reasons = [...baselineIncreases(baseBaseline, headBaseline), ...guardedChanges(changedPaths)];
  if (reasons.length === 0) return { status: 'not-needed', reasons, stale: false, comment: null };

  const list = reasons.map((r) => `- ${r}`);
  const label = currentLabel(labelEvents);
  const pushedAt = latestPushAt ? Date.parse(latestPushAt) : NaN;
  if (label && Date.parse(label.at) > pushedAt) {
    const by = label.actor ? ` by @${label.actor}` : '';
    const comment = [
      APPROVAL_MARKER,
      `**Guardrail approval: approved${by}** (label \`${APPROVAL_LABEL}\` added ${label.at}, after the latest push).`,
      '',
      'Approved changes:',
      ...list,
      '',
      'A new push makes this approval stale.'
    ].join('\n');
    return { status: 'approved', reasons, stale: false, comment };
  }

  const stale = Boolean(label);
  const comment = [
    APPROVAL_MARKER,
    `**Guardrail approval needed.** This pull request changes a guardrail; a human must review it and add the ` +
      `\`${APPROVAL_LABEL}\` label:`,
    '',
    ...list,
    '',
    ...(stale
      ? [
          `The approval is **stale**: the label was added ${label.at}, before the latest push` +
            `${latestPushAt ? ` (${latestPushAt})` : ' (time unknown)'}. Review the new commits, then remove and add ` +
            `the label again (the job removes a stale label itself when it can).`,
          ''
        ]
      : []),
    'Adding the label re-runs this check; no new push is needed.'
  ].join('\n');
  return { status: 'needed', reasons, stale, comment };
}
