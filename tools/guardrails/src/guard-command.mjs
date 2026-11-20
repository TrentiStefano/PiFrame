/**
 * Guard command: decides whether an agent may run a shell command.
 *
 * Agents share the maintainer's GitHub login, so nothing on GitHub stops them from approving their own changes.
 * This guard blocks the obvious ways: any `gh` invocation that mentions `human-approved`, and `gh label
 * create|edit|delete`. It is a speed bump, not a security boundary.
 */

import { APPROVAL_LABEL } from './approval.mjs';

// A word `gh` (or `gh.exe`, possibly behind a path), not part of a longer word such as `github` or `gh-pages`.
const GH_WORD = /(?<![\w.-])gh(?:\.exe)?(?![\w.-])/gi;

// Characters after which the next word is in command position: start of a command, a pipeline or a list, a
// subshell, a block, a quoted script (`sh -c "gh ..."`) or the PowerShell call operator (`& gh`).
const COMMAND_START = /[;&|(){}`"'\r\n]$/;

// Words that run their argument as a command (`sudo gh`, `xargs gh`, `Start-Process gh`, `cmd /c gh`).
const LAUNCHERS = new Set([
  'sudo',
  'env',
  'exec',
  'command',
  'time',
  'nohup',
  'xargs',
  'npx',
  'pnpx',
  'call',
  'start',
  'start-process',
  'saps',
  'iex',
  'invoke-expression',
  '/c',
  '/k'
]);

function precededByCommandStart(before) {
  if (/[\\/]$/.test(before)) return true; // a path such as /usr/bin/gh or C:\...\gh.exe
  const trimmed = before.trimEnd();
  if (trimmed === '' || COMMAND_START.test(trimmed)) return true;
  const previousWord = trimmed.split(/\s+/).pop().toLowerCase();
  // A launcher, an option of one (`bash -lc gh`, `xargs -n1 gh`) or an environment assignment (`GH_TOKEN=x gh`).
  return LAUNCHERS.has(previousWord) || previousWord.startsWith('-') || /^\w+=/.test(previousWord);
}

/** Offsets at which `gh` is invoked (in command position), in order. */
function ghInvocations(command) {
  return [...command.matchAll(GH_WORD)]
    .filter((match) => precededByCommandStart(command.slice(0, match.index)))
    .map((match) => match.index + match[0].length);
}

// Quotes, escapes and concatenation that shells drop before the label reaches gh (`human-"approved"`).
const normalize = (text) => text.replace(/["'`^\\+\s]/g, '').toLowerCase();

const GH_LABEL_SUBCOMMAND = /^\s+label\s+(create|edit|delete)\b/i;

export function guardCommand(command) {
  const invocations = ghInvocations(command);
  if (invocations.length > 0 && normalize(command.slice(invocations[0])).includes(APPROVAL_LABEL)) {
    return {
      decision: 'block',
      reason:
        `Blocked: agents may not apply the ${APPROVAL_LABEL} label; only the human approves, in the GitHub UI. ` +
        `If the command only mentions the label in prose (an issue or PR body or comment), write the text to a ` +
        `file and pass it with --body-file instead.`
    };
  }
  const labelSubcommand = invocations
    .map((offset) => command.slice(offset).replace(/["'`]/g, '').match(GH_LABEL_SUBCOMMAND))
    .find(Boolean);
  if (labelSubcommand) {
    return {
      decision: 'block',
      reason: `Blocked: agents may not ${labelSubcommand[1].toLowerCase()} labels; ask the human to change labels in GitHub.`
    };
  }
  return { decision: 'allow' };
}
