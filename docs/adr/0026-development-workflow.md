# ADR 0026: Development Workflow: Three Routes, One Gate, Human Approval

- **Status:** Accepted
- **Confirmation Date:** 2026-11-25

## Context

PiFrame moves to agent-driven development in six phases (parent spec #85). Phases 1 to 5 built the pieces: one gate
shared by agents and CI (#41), the Flutter and Dart tooling (#51), the agent context and the review artifacts (#62 and #70),
and the golden screens (#80). Each closed spec explains its own piece, but nothing said how the pieces fit into a routine,
and the reasons were spread across closed issues that are hard to find.

The methodology needs a short, fixed set of decisions that every agent and the maintainer can rely on, and a single place
where the decisions are recorded.

## Decision

1. **Three routes.** Every piece of work follows one of three routes, chosen before starting: feature or design decision
   (grill, spec, tickets, implement, pull request), bug (diagnose, failing regression test, fix, pull request), and small
   change with no design decision (test-first implementation, pull request, no spec). The routes and their steps are in
   [the development workflow guide](../development-workflow.md). A design decision found during a small change moves the
   work to the feature route.

2. **Specs are GitHub issues, decided by the maintainer.** Design decisions are settled in a grilling session before
   implementation. The spec is a GitHub issue, its tickets are sub-issues, and the maintainer approves the ticket breakdown.
   Decisions that outlive the spec go to `docs/adr/`.

3. **One gate, with ratchets.** `pnpm run check` is the inner loop and `pnpm run verify` is the full gate. CI runs the same
   steps as `verify`, and both run on pull requests. Counts that must not grow (escape hatches, diagnostics, TypeScript
   ratchet, import boundaries) live in committed baselines: a count may go down freely and only goes up with approval.

4. **Human approval, with expiry.** A change to a guardrail needs the `human-approved` label on the pull request. The label
   counts only when it was added after the latest push, so an approval never covers code the maintainer has not seen.
   Lowering a baseline needs no label. The approval logic runs from the base branch, so a pull request cannot change the
   logic that judges it.

5. **Agent guards.** Agents are held to the gate by their guards, not by prose: the escape-hatch audit refuses
   `as any`, `: any`, `// ignore:` and similar suppressions; the map and link checks keep the agent context true; the
   agent-guard files (`.claude/settings.json`, hooks and the other agents' rule files) are guarded paths. A rule an agent
   must follow is written as a check where a check is possible.

6. **Golden tests for the key screens.** Four screens in light and dark at 1920 by 1032 are compared against committed
   reference images. The comparison runs on Windows in `verify` only, because the references come from one platform and
   the inner loop must stay fast. The reference images are a guarded path, so every visual change is approved by the
   maintainer.

7. **English only.** Code, comments, documents, ADRs, issues and specs are in English, so that agents and contributors read
   one language. The user interface text goes through the language files in `apps/pi_frame/lib/data/language/`.

8. **Documentation rules.** Documents have one purpose each (AGENTS.md rule 4). A bug fix leaves a regression test or a
   lint. Troubleshooting changes only for problems users must work around, and installation only when installing or
   operating the app changes. Developer tooling is documented in the developer docs and package READMEs.

9. **Retro findings become checks or decisions.** `/retro` findings become a `needs-triage` issue naming the lint, test or
   check to add, or an ADR when the finding is a decision. A finding never becomes a new prose rule in AGENTS.md.

10. **The architecture review is manual.** `improve-codebase-architecture` runs by hand as the last step of every closed
    spec, and its findings become specs. No scheduled or background agent runs it.

11. **The model is the operator's choice.** The methodology names no model for agents. Whoever runs an agent chooses it.

## Consequences

An agent or the maintainer picks one of three routes in a line of AGENTS.md and finds the detail in one guide. The gate
carries the rules, so a rule added after a retro costs a check, not a paragraph in the agent context. The maintainer's
effort concentrates on three things: the answers to the grilling, the approval of the ticket breakdown and the approval
label on guarded changes. The cost is that guarded changes wait for a human, and that approval expires on every push,
so the maintainer re-approves after each change to a guarded path.

## Alternatives Rejected

A single generic workflow line in AGENTS.md (agents could not tell a feature from a bug from a small change); a model rule
for agents (the operator chooses per run); a scheduled architecture-review agent (it spends usage on work nobody asked
for); approvals that stay valid after new pushes (the maintainer would approve code they have not seen); golden tests in
the inner loop (the references are platform-specific and the inner loop would slow down).
