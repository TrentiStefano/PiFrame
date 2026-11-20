#!/usr/bin/env node
// Claude Code PreToolUse hook for the Bash and PowerShell tools: denies commands the shared agent guard blocks
// (applying the human-approved label, editing labels). The decision logic lives in tools/guardrails.
// Try it: echo '{"tool_name":"Bash","tool_input":{"command":"gh pr edit 999999 --add-label human-approved"}}' | node .claude/hooks/guard-command.mjs
import { guardCommand } from '../../tools/guardrails/src/index.mjs';

let input = '';
for await (const chunk of process.stdin) input += chunk;

const command = JSON.parse(input).tool_input?.command;
if (typeof command === 'string') {
  const result = guardCommand(command);
  if (result.decision === 'block') {
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: 'deny',
          permissionDecisionReason: result.reason
        }
      })
    );
  }
}
