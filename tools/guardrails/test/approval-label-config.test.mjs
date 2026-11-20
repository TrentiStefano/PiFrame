import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { APPROVAL_LABEL } from '../src/index.mjs';

// Config files that cannot import the constant spell the label out; renaming it must update them too.
const LITERAL_COPIES = [
  '.claude/settings.json',
  '.codex/rules/guard.rules',
  '.github/workflows/guardrails-approval.yml'
];

for (const file of LITERAL_COPIES) {
  test(`${file} names the approval label APPROVAL_LABEL holds`, () => {
    const text = readFileSync(fileURLToPath(new URL(`../../../${file}`, import.meta.url)), 'utf8');
    assert.ok(
      text.includes(APPROVAL_LABEL),
      `${file} does not mention "${APPROVAL_LABEL}": update its copy of the label`
    );
  });
}
