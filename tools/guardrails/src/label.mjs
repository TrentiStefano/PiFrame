/**
 * The label a human adds to a pull request to approve a guardrail change. Its own module so the approval logic,
 * the escape-hatch messages and the agent guard share it without importing each other. Config files that cannot
 * import it (.claude/settings.json, .codex/rules, the approval workflow) repeat the literal; a test keeps them in sync.
 */
export const APPROVAL_LABEL = 'human-approved';
