#!/usr/bin/env node
// Antigravity PreToolUse hook for run_command (registered in .agents/hooks.json): denies commands the shared agent
// guard blocks (applying the human-approved label, editing labels). The decision logic lives in tools/guardrails.
// An allowed command gets no decision, so Antigravity applies the user's own permission settings.
// Try it: echo '{"toolCall":{"name":"run_command","args":{"CommandLine":"gh label delete wip"}}}' | node .agents/hooks/guard-command.mjs
import { guardCommand } from '../../tools/guardrails/src/index.mjs';

let input = '';
for await (const chunk of process.stdin) input += chunk;

const command = JSON.parse(input).toolCall?.args?.CommandLine;
const result = typeof command === 'string' ? guardCommand(command) : { decision: 'allow' };
process.stdout.write(JSON.stringify(result.decision === 'block' ? { decision: 'deny', reason: result.reason } : {}));
