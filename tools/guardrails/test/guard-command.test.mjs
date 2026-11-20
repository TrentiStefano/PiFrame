import test from 'node:test';
import assert from 'node:assert/strict';
import { guardCommand } from '../src/index.mjs';

const assertBlocked = (command) => {
  const result = guardCommand(command);
  assert.equal(result.decision, 'block', `expected a block for: ${command}`);
  assert.match(result.reason, /\S/);
};

const assertAllowed = (command) => {
  assert.deepEqual(guardCommand(command), { decision: 'allow' }, `expected no block for: ${command}`);
};

test('blocks adding the human-approved label to a PR', () => {
  assertBlocked('gh pr edit 1 --add-label human-approved');
});

test('blocks the label in any position, quoting or case', () => {
  assertBlocked('gh pr edit --add-label human-approved 1');
  assertBlocked('gh issue edit 7 --add-label "ready-for-agent,human-approved"');
  assertBlocked("gh pr edit 1 --add-label 'Human-Approved'");
  assertBlocked('gh pr edit 1 --add-label human-"approved"');
  assertBlocked('gh -R TrentiStefano/PiFrame pr edit 1 --add-label=human-approved');
  assertBlocked('cd apps && gh pr edit 1 --add-label human-approved');
  assertBlocked('GH_TOKEN=x gh pr edit 1 --add-label human-approved');
  assertBlocked('/usr/bin/gh pr edit 1 --add-label human-approved');
  assertBlocked('gh pr create --label human-approved --fill');
});

test('blocks the label inside sh -c, bash -c and PowerShell', () => {
  assertBlocked('sh -c "gh pr edit 1 --add-label human-approved"');
  assertBlocked("bash -lc 'cd /repo; gh pr edit 1 --add-label human-approved'");
  assertBlocked("& gh pr edit 1 --add-label 'human-approved'");
  assertBlocked('& "C:\\Program Files\\GitHub CLI\\gh.exe" pr edit 1 --add-label human-approved');
  assertBlocked("$l = 'x'; gh pr edit 1 --add-label ('human-' + 'approved')");
  assertBlocked('powershell -Command "gh pr edit 1 --add-label human-approved"');
  assertBlocked('Start-Process gh -ArgumentList "pr edit 1 --add-label human-approved"');
});

test('blocks the label in gh api calls', () => {
  assertBlocked('gh api repos/TrentiStefano/PiFrame/issues/1/labels -f "labels[]=human-approved"');
  assertBlocked('gh api --method POST repos/o/r/issues/1/labels --input - <<< \'{"labels":["human-approved"]}\'');
  assertBlocked('gh api -X PATCH repos/o/r/labels/wip -f new_name=human-approved');
});

test('blocks creating, editing and deleting labels', () => {
  assertBlocked('gh label create needs-review --color FF0000');
  assertBlocked('gh label edit wip --name approved');
  assertBlocked('gh label delete ready-for-agent --yes');
  assertBlocked('sh -c "gh label delete wip --yes"');
  assertBlocked('& gh label  edit wip --description x');
});

test('allows reading labels', () => {
  assertAllowed('gh label list');
});

test('allows the labels, sub-issue links and dependencies the engineering skills use', () => {
  assertAllowed('gh issue create --title "Phase 1.7" --body-file body.md --label ready-for-agent');
  assertAllowed('gh issue create --label wayfinder:map --title Map --body x');
  assertAllowed('gh issue edit 46 --add-label ready-for-agent --remove-label needs-triage');
  assertAllowed('gh pr edit 12 --add-label migration');
  assertAllowed('gh issue create --parent 41 --blocked-by 42,43 --title x --body y');
  assertAllowed('gh issue edit 46 --add-blocked-by 42');
  assertAllowed('gh issue edit 41 --add-sub-issue 46');
  assertAllowed('gh issue edit 46 --add-assignee @me');
  assertAllowed('gh api --method POST repos/TrentiStefano/PiFrame/issues/46/dependencies/blocked_by -F issue_id=123');
  assertAllowed('gh api --method POST repos/TrentiStefano/PiFrame/issues/41/sub_issues -F sub_issue_id=456');
  assertAllowed('gh api repos/TrentiStefano/PiFrame/issues/46 --jq .issue_dependencies_summary.blocked_by');
  assertAllowed('gh issue view 46 --json number,title,body,labels,comments');
});

test('the block reason sends approval to the human and points prose about the label to a body file', () => {
  const { reason } = guardCommand('gh issue comment 46 --body "This PR needs human-approved"');
  assert.match(reason, /human/i);
  assert.match(reason, /--body-file/);
});

test('allows commands that mention the label without invoking gh', () => {
  assertAllowed('git commit -m "docs: explain when the human-approved label is needed"');
  assertAllowed('git commit -m "feat: the guard blocks gh pr edit with human-approved"');
  assertAllowed('grep -rn human-approved docs/');
  assertAllowed('git commit -m "require human-approved" && gh pr create --fill');
});
