---
name: bugfix
description: Take a PiFrame bug report from description to open pull request, unattended — issue, branch, diagnosis, failing regression test, root-cause fix, gate, PR. Use only when the maintainer runs /bugfix <description>.
disable-model-invocation: true
---

# Bugfix

The maintainer gives a bug report; you run the whole bug route of `docs/development-workflow.md` and stop at an open
pull request. Running `/bugfix` is the maintainer's go-ahead to create the issue, the branch, the commits, the push and
the PR. Never merge the PR, and never add, remove or name the approval label in a command (the agent guard blocks it).

## 1. Understand the report

Read `AGENTS.md`, `GLOSSARY.md` and the "Route 2: bug" section of `docs/development-workflow.md`, then the ADRs of the
affected area. If the report says neither what happens nor what should happen, ask one question — "What do you see, and
what should happen instead?" — and wait. Otherwise do not ask; start.

## 2. Issue and branch

1. Look for an existing issue: `gh issue list --repo TrentiStefano/PiFrame --state open --search "<keywords>"`. Reuse a
   clear match; otherwise create one with the `bug` label. Write the body to a file and pass `--body-file`, never inline:

   ```markdown
   ## Symptom
   <what the maintainer sees, in their words>
   ## Expected
   <what should happen>
   ## Repro
   <steps, or "to be found">
   ```

2. Branch from the latest `main`: `git fetch origin`, then
   - working tree clean: `git switch -c fix/<issue>-<short-name> origin/main`;
   - working tree dirty: leave it alone and use a worktree outside the repository folder:
     `git worktree add ../PiFrame-fix-<issue> -b fix/<issue>-<short-name> origin/main`, then `pnpm run setup` there.

## 3. Diagnose

Follow the `diagnosing-bugs` skill to its completion criterion. First build one fast, unattended feedback loop that
shows the reported symptom: a failing test, a replay, a fake-pi scenario (`tools/fake-pi/`) or, for UI behaviour, the
real app through `.agents/skills/piframe-ui-harness/SKILL.md`. Then minimise it, rank 3–5 falsifiable hypotheses and
probe one variable at a time. Remove every temporary probe and log line afterwards.

When the cause is verified, comment it on the issue (body file): the root cause in one or two sentences, and the
file and function it lives in.

## 4. Red, then green

Follow the `tdd` skill.

1. Turn the minimised repro into a regression test at the highest seam that shows the bug, in the module's own test
   folder (`AGENTS.md`, Conventions). Run it; it must fail for the reported symptom. Keep the failing output for the PR.
2. Fix the root cause with the smallest change. For a protocol fix, change `packages/pcp-spec/schema/` first, then
   `pnpm run codegen`. User-facing text goes through `apps/pi_frame/lib/data/language/`.
3. Run the test; it must pass. Re-run the original, unminimised repro.
4. If the same mistake could recur elsewhere, add a lint or gate check as well (`AGENTS.md`, Gate checks).
5. Docs, per `AGENTS.md` rule 4: `docs/troubleshooting.md` only if users had to work around it, `docs/user-guide.md`
   only if documented behaviour changes.

Never pass a check with an escape hatch, a lint suppression, a raised baseline or a weakened test (rule 5).

## 5. Gate and PR

1. `pnpm run check -- <test files>` while iterating, then `pnpm run check`. For daemon and protocol changes also run
   the affected package tests; for cross-layer behaviour `pnpm run test:e2e`.
2. Commit the test and the fix (Conventional Commits, `fix(<area>): ...`, with `Refs #<issue>`).
3. Write the PR body with the `pr` skill from `.github/pull_request_template.md`: `Closes #<issue>`, root cause and fix,
   the red and green test output as evidence, Merge Danger, and Guardrail changes (`none` unless you touched one).
4. `pnpm run pr -- --title "fix(<area>): <summary>" --body-file <file>`. It runs `verify`, pushes and opens the PR. If a
   step fails, nothing is pushed: fix the root cause and run it again.

## Stop and ask only for these

- No repro is possible, or you need access or an artifact you do not have.
- The evidence supports more than one expected behaviour.
- The fix changes the protocol, a UX behaviour, security, or stored data on disk.
- The fix is really a design decision: stop, say so, and suggest the feature route (grilling, then a spec).

Ordinary test results, a successful check and routine diagnosis are not reasons to stop.

## Done

Report in a few lines: the issue and PR links, the root cause, the regression test, and anything left to the
maintainer. If the PR touches a guarded path (`tools/guardrails/src/approval.mjs`: gate scripts, baselines, workflows,
agent guard, goldens, `DESIGN.md`), say that its approval check waits for the maintainer's label. If the bug was hard —
long to find, or the gate should have caught it — suggest `/retro`: its findings become a `needs-triage` issue naming a
check, or an ADR, never a new prose rule in `AGENTS.md`.
