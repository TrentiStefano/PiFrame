# ADR 0024: Dense Transcript and Quiet Chrome

- **Status:** Accepted
- **Confirmation Date:** 2026-11-23
- **Stakeholder Decision Reference:** old DESIGN.md design decision log, "D9 round-5 density, hierarchy and anti-slop refinement" (2026-10-07), and review round 6

## Context

In live review the user found the app monochrome, the chat padded with a bordered card for every reasoning block and tool call, a tall window toolbar, pane headers that did not match, monospace file names in the repository tree, centred user messages and a cluttered composer. The user also named an anti-reference: the "AI-generated" look where every box has a fill, a lighter outline and text all in the same hue.

## Decision

1. Intermediate agent activity (reasoning, tool calls, commands) renders as compact, borderless rows with the status and duration aligned on the right, expandable for details, and grouped into a step group above the final answer.
2. No same-hue triple tint: surfaces stay neutral, text stays readable, and colour appears in small semantic sparks (file-type icons, Git `+n -n` counts, syntax and diff colours, status dots).
3. The repository tree uses the UI font; mono is reserved for code, diffs, paths shown as paths, and numbers.
4. The chrome is slim and uniform: a 40 px title bar with a small wordmark, and the same 40 px flat header on the chat, repository, Git Changes and review panes.
5. User messages are indented towards the right; assistant messages align left.
6. The transcript scrollbar shows the thumb only, with no track.
7. The composer is one card: the text field above, the model, thinking and context pickers bottom-left, and icon actions (expand, attach, review changes, send) bottom-right.

## Consequences

The transcript shows several steps in the space one bordered card used to take, and the final answer stays the most prominent block. The sizes are tokens (`FrameSize.paneHeader`, `FrameSize.rowList`), and `DESIGN.md` describes the resulting components. The original round set the toolbar at 42 px and headers at 38 px; both later moved to the shared 40 px token.

## Alternatives Rejected

Keeping one bordered card per step (too much chrome for long runs); a two-colour accent wash across the UI (monotonous and hard to scan).
