---
name: bugfix
description: Take one PiFrame bug report, or a list of them, from description to open pull requests, unattended — issues, a worktree, diagnosis, failing regression tests, root-cause fixes, gate, PRs. Use only when the maintainer runs /bugfix <description or list>.
disable-model-invocation: true
---

# Bugfix

The maintainer gives one bug report or a list of them; you run the bug route of `docs/development-workflow.md` for each
and stop at open pull requests. Running `/bugfix` is the maintainer's go-ahead to create the issues, the branches, the
commits, the pushes and the PRs. Never merge a PR, and never add, remove or name the approval label in a command (the
agent guard blocks it).

**Nothing local goes to GitHub.** Issues, comments, commit messages and the PR are public. Never write an absolute
local path (`C:\Users\...`, `/Users/...`, `/home/...`), a username or a machine name, even when the report contains
one. Refer to a file the maintainer attached by its name only ("the attached screenshot"), and to repository files by
their path relative to the repository root. The PR-body check refuses local paths; for issues, comments and commit
messages, you are the check.

**One bug at a time, in your own worktree.** Never work in the maintainer's checkout, and never fix two bugs at once or
run two `verify`s at once: they share the machine's build output and the verify log. A list is worked through in order.

## 1. Understand the reports

Read `AGENTS.md`, `GLOSSARY.md` and the "Route 2: bug" section of `docs/development-workflow.md`, then the ADRs of the
affected areas. A list (bullets or numbered lines) is one bug per item.

Before any code, check every report: it must say what happens and what should happen instead. Collect the questions for
all unclear items into **one** message ("What do you see, and what should happen instead?" per item) and wait for the
answers. If every report is clear, do not ask; start.

## 2. Issues, groups and worktree

1. For each bug, look for an existing issue: `gh issue list --repo TrentiStefano/PiFrame --state open --search
   "<keywords>"`. Reuse a clear match; otherwise create one with the `bug` label. Write the body to a file and pass
   `--body-file`, never inline:

   ```markdown
   ## Symptom
   <what the maintainer sees, in their words, with every local path removed>
   ## Expected
   <what should happen>
   ## Repro
   <steps, or "to be found">
   ```

2. Group a list into PRs (a single report is one group). Bugs in the same area — the same daemon module, the same app
   feature, the same package — share a group. A bug gets a group of its own when its fix may change the protocol, a UX
   behaviour, security or stored data, or when it touches a guarded path: it must be reviewable and revertable alone.
   Order the groups so that a group whose fix another one builds on goes first.
3. Create one worktree outside the repository folder, from the latest `main`:
   `git fetch origin`, `git worktree add ../PiFrame-bugfix-<first issue> origin/main --detach`, then `pnpm run setup`
   there. Reuse it for every group: start each group with
   `git fetch origin && git switch -c fix/<issues>-<short-name> origin/main`.

## 3. Diagnose (per bug)

Follow the `diagnosing-bugs` skill to its completion criterion. First build one fast, unattended feedback loop that
shows the reported symptom: a failing test, a replay, a fake-pi scenario (`tools/fake-pi/`) or, for UI behaviour, the
real app through `.agents/skills/piframe-ui-harness/SKILL.md`. Then minimise it, rank 3–5 falsifiable hypotheses and
probe one variable at a time. Remove every temporary probe and log line afterwards.

For a slow or stuck screen, read the daemon log first: `~/.piframe/runtime/daemon.log` (dev builds:
`~/.piframe-dev/runtime/daemon.log`) lists every slow command with its duration and every event-loop stall.

When the cause is verified, comment it on the issue (body file): the root cause in one or two sentences, and the
file and function it lives in.

## 4. Red, then green (per bug)

Follow the `tdd` skill.

1. Turn the minimised repro into a regression test at the highest seam that shows the bug, in the module's own test
   folder (`AGENTS.md`, Conventions). Run it; it must fail for the reported symptom. Keep the failing output for the PR.
2. Fix the root cause with the smallest change. For a protocol fix, change `packages/pcp-spec/schema/` first, then
   `pnpm run codegen`. User-facing text goes through `apps/pi_frame/lib/data/language/`.
3. Run the test; it must pass. Re-run the original, unminimised repro.
4. If the same mistake could recur elsewhere, add a lint or gate check as well (`AGENTS.md`, Gate checks).
5. Docs, per `AGENTS.md` rule 4: `docs/troubleshooting.md` only if users had to work around it, `docs/user-guide.md`
   only if documented behaviour changes.
6. Commit the test and the fix as **one commit per bug** (Conventional Commits, `fix(<area>): ...`, `Refs #<issue>`),
   so a single fix can be reverted on its own.

Never pass a check with an escape hatch, a lint suppression, a raised baseline or a weakened test (rule 5).

## 5. Gate and PR (per group)

1. `pnpm run check -- <test files>` while iterating, then `pnpm run check`. For daemon and protocol changes also run
   the affected package tests; for cross-layer behaviour `pnpm run test:e2e`.
2. Write the PR body with the `pr` skill from `.github/pull_request_template.md`: `Closes #a, closes #b` for every bug
   in the group, the root cause and fix of each, the red and green test output of each as evidence, Merge Danger, and
   Guardrail changes (`none` unless you touched one).
3. `pnpm run pr -- --title "fix(<area>): <summary>" --body-file <file>`. It runs `verify`, pushes and opens the PR. If a
   step fails, nothing is pushed: fix the root cause and run it again. Then move to the next group.

## Stop, or skip, only for these

- No repro is possible, or you need access or an artifact you do not have.
- The evidence supports more than one expected behaviour.
- The fix changes the protocol, a UX behaviour, security, or stored data on disk.
- The fix is really a design decision: say so, and suggest the feature route (grilling, then a spec).

With a single report, stop and ask. With a list, do not stop the batch: write the question on that bug's issue (body
file), add the `needs-info` label, leave the bug out of its group, and go on with the next one. Ask all the skipped
questions together in the final report.

Ordinary test results, a successful check and routine diagnosis are not reasons to stop.

## Done

Remove the worktree (`git worktree remove ../PiFrame-bugfix-<first issue>`; the branches stay on GitHub). Then report,
for a list as a table, each bug with its issue, its PR (or "skipped" and the open question), the root cause and the
regression test. Say which PRs touch a guarded path (`tools/guardrails/src/approval.mjs`: gate scripts, baselines,
workflows, agent guard, goldens, `DESIGN.md`) and so wait for the maintainer's label. If a bug was hard — long to find,
or the gate should have caught it — suggest `/retro`: its findings become a `needs-triage` issue naming a check, or an
ADR, never a new prose rule in `AGENTS.md`.
