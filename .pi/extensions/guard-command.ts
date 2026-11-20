// pi project extension: blocks bash and PowerShell commands the shared agent guard rejects (applying the
// human-approved label, editing labels). The decision logic lives in tools/guardrails. pi loads it once the project
// is trusted.
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import { guardCommand } from '../../tools/guardrails/src/index.mjs';

const SHELL_TOOLS = new Set(['bash', 'powershell']);

export default function (pi: ExtensionAPI) {
  pi.on('tool_call', async (event) => {
    if (!SHELL_TOOLS.has(event.toolName)) return undefined;
    const command = (event.input as { command?: unknown }).command;
    if (typeof command !== 'string') return undefined;
    const result = guardCommand(command);
    return result.decision === 'block' ? { block: true, reason: result.reason } : undefined;
  });
}
