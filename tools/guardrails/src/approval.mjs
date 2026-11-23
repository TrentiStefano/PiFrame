/**
 * Approval status: decides whether a pull request changes a guardrail and, if so, whether a human approved it.
 *
 * A PR needs approval when it raises a number in the escape-hatch baseline (lowering is free) or changes a guarded
 * path (analyzer options, tsconfig, formatter/linter configs, guardrail tooling, workflows, the agent guards, AGENTS.md). It is
 * approved only when the `human-approved` label is on the PR and was added after the latest push: an older label
 * is stale, because the human has not seen the newer commits.
 *
 * Pure: no I/O. tools/scripts/guardrails-approval.mjs (run by .github/workflows/guardrails-approval.yml) reads git
 * and GitHub and calls it. See docs/pr-verification.md.
 */
import { AGENT_MAP_PATH } from './agent-map.mjs';
import { BASELINE_PATH } from './escape-hatches.mjs';
import { APPROVAL_LABEL } from './label.mjs';
import { basename, SCRIPT_FILE, toPosix } from './paths.mjs';
import { stepList } from './steps.mjs';

export { APPROVAL_LABEL };
/** Hidden marker that identifies the job's one comment, so it is updated instead of duplicated. */
export const APPROVAL_MARKER = '<!-- guardrails-approval -->';

/**
 * Every script file a gate step runs, in every tier (release and e2e steps included): changing one could make a
 * check exit 0 without doing its job. Derived from the step list, so a new step's script is guarded automatically.
 */
const GATE_SCRIPTS = new Set(
  [
    ...stepList('verify', { release: true, e2e: true, platform: 'linux', appVersion: '0.0.0' }),
    ...stepList('ci'),
    ...stepList('check')
  ].flatMap(({ command, cwd }) =>
    command.filter((arg) => !arg.startsWith('-') && SCRIPT_FILE.test(arg)).map((arg) => (cwd ? `${cwd}/${arg}` : arg))
  )
);

/** Guarded single files that are not caught by a name or folder rule below. */
const TOOLING_FILES = new Set([
  'tools/scripts/flutter-projects.json',
  'tools/scripts/guardrails-approval.mjs',
  'tools/scripts/verify-ci.mjs',
  'tools/scripts/check.mjs',
  'pnpm-workspace.yaml'
]);
const TOOLING_DIRS = ['tools/guardrails/', 'tools/codegen/'];
const AGENT_GUARD_FILES = new Set(['.claude/settings.json']);
const AGENT_GUARD_DIRS = ['.claude/hooks/', '.pi/extensions/', '.codex/rules/'];

/** Why a path is guarded, or undefined when changing it needs no approval. */
function guardedKind(path) {
  if (path === BASELINE_PATH) return undefined; // only its increases need approval, see baselineIncreases
  const name = basename(path);
  if (name === 'analysis_options.yaml') return 'Dart analyzer options';
  if (/^tsconfig.*\.json$/.test(name)) return 'TypeScript config';
  if (name === '.prettierrc.json' || name === '.prettierignore') return 'formatter config';
  if (/^(\.eslintrc(\..+)?|\.eslintignore|eslint\.config\.[cm]?[jt]s)$/.test(name)) return 'linter config';
  if (path.startsWith('.github/workflows/')) return 'CI workflow';
  if (GATE_SCRIPTS.has(path)) return 'gate script';
  if (TOOLING_FILES.has(path) || TOOLING_DIRS.some((dir) => path.startsWith(dir))) return 'guardrail tooling';
  // The `build`, `lint` and `test` scripts the gate runs, and the pinned Prettier version, live in package.json.
  if (name === 'package.json' && !path.split('/').includes('node_modules')) return 'package manifest';
  if (AGENT_GUARD_FILES.has(path) || AGENT_GUARD_DIRS.some((dir) => path.startsWith(dir))) return 'agent guard';
  // The agents' rules and map (the agent map check keeps it short and correct, tools/guardrails/src/agent-map.mjs).
  if (path === AGENT_MAP_PATH) return 'agent instructions';
  return undefined;
}

function guardedChanges(changedPaths) {
  const paths = [...new Set(changedPaths.map(toPosix))].sort();
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

/** Pull-request events that are a push: a run they trigger was created by that push. */
const PUSH_ACTIONS = new Set(['opened', 'synchronize', 'reopened']);

/**
 * The latest push time GitHub recorded (commit dates are written by whoever commits, so they are never used): this
 * run's creation time when a push triggered it, and the newest `ci.yml` pull-request run for the head commit
 * (ci.yml runs on exactly the push events). Null when neither is known.
 */
function latestPush({ eventAction, runCreatedAt, ciRunTimes = [] }) {
  const times = [...(PUSH_ACTIONS.has(eventAction) ? [runCreatedAt] : []), ...ciRunTimes].filter(
    (t) => t && !Number.isNaN(Date.parse(t))
  );
  return times.sort((a, b) => Date.parse(a) - Date.parse(b)).at(-1) ?? null;
}

const NOT_NEEDED_ANY_MORE =
  `${APPROVAL_MARKER}\n**Guardrail approval: not needed.** Nothing in this pull request changes a guardrail any ` +
  `more.`;

/**
 * @param {object} input
 * @param {object} input.baseBaseline escape-hatch baseline on the PR's base
 * @param {object} input.headBaseline escape-hatch baseline on the PR's head
 * @param {string[]} input.changedPaths paths the PR changes (renames as both old and new path)
 * @param {{ action: 'labeled' | 'unlabeled', label: string, at: string, actor?: string }[]} input.labelEvents the
 *   PR's label events, with the time GitHub recorded them (ISO 8601)
 * @param {string} [input.eventAction] the pull-request event that triggered this run (`opened`, `labeled`, ...)
 * @param {string} [input.runCreatedAt] when GitHub created this run (ISO 8601)
 * @param {string[]} [input.ciRunTimes] creation times of the `ci.yml` pull-request runs for the head commit
 * @param {string | null} [input.previousComment] the body of this job's earlier comment on the PR, if any
 * @returns {{ status: 'not-needed' | 'needed' | 'approved', reasons: string[], stale: boolean,
 *   latestPushAt: string | null, comment: string | null }} `comment` is the body the PR's one comment should have,
 *   or null when the PR needs no comment; any label counts as stale when `latestPushAt` is null
 */
export function approvalStatus({
  baseBaseline,
  headBaseline,
  changedPaths = [],
  labelEvents = [],
  eventAction,
  runCreatedAt,
  ciRunTimes = [],
  previousComment = null
}) {
  const reasons = [...baselineIncreases(baseBaseline, headBaseline), ...guardedChanges(changedPaths)];
  const latestPushAt = latestPush({ eventAction, runCreatedAt, ciRunTimes });
  if (reasons.length === 0) {
    // An earlier push needed approval and this one does not: say so instead of leaving an outdated comment.
    const comment = previousComment ? NOT_NEEDED_ANY_MORE : null;
    return { status: 'not-needed', reasons, stale: false, latestPushAt, comment };
  }

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
    return { status: 'approved', reasons, stale: false, latestPushAt, comment };
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
  return { status: 'needed', reasons, stale, latestPushAt, comment };
}
