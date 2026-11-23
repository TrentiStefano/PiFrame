# ADR 0023: Own PiFrame Light and Dark Themes with One Surface Grammar

- **Status:** Accepted
- **Confirmation Date:** 2026-11-23
- **Stakeholder Decision Reference:** old DESIGN.md design decision log, "D9 live-review revision" and "D9 round-4 visual correction" (2026-10-07)

## Context

The first design rounds used a borrowed palette and square, borderless surfaces outside the main panes. In live review the user found the selected themes still rendered the old colours, light-theme controls that were nearly black, and an inconsistent mix of rounded panes and square settings, rows, dialogs and inputs. The user also retired the external design languages that earlier rounds had referenced.

## Decision

1. PiFrame ships its own two default themes, PiFrame Light and PiFrame Dark (`themes/piframe-light.json`, `themes/piframe-dark.json`), with a steel-blue accent and semantic roles (surfaces, text, status, agent states, diff, syntax). Every widget takes its colours from these roles; the light and dark values are tuned separately for contrast.
2. One surface grammar holds across the whole app, not only the main panes: flat surfaces, a 1 px hairline border and the semantic radii (6, 10 and 14 px) on panes, settings sections, rows, transcript blocks, the composer, dialogs, menus and inputs. No square borderless cards, glass, gradients or nested card stacks.
3. The design no longer follows any external product's visual language; PiFrame keeps its own name, mark and bundled typography.

## Consequences

The tokens in `DESIGN.md` mirror the two theme files, and the gate checks that they match. User themes and imported VS Code themes map onto the same roles, so they restyle the app without changing its shapes.

## Alternatives Rejected

Keeping a third-party palette (it could not carry PiFrame's status and diff roles at readable contrast without custom hues, which then no longer matched the palette); styling only the three main panes (the rest of the app looked unfinished next to them).
