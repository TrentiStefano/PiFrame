# ADR 0025: Pi Commands Are Command Chips, Not Text

- **Status:** Accepted
- **Confirmation Date:** 2026-11-23
- **Stakeholder Decision Reference:** old DESIGN.md design decision log, "Pi commands are tokens, not text" (2026-11-11)

## Context

The user could not tell a typed Pi command from a chat message, and `/reload` was posted to the chat as a user message instead of reloading Pi: the composer only recognised built-in commands when the command list had already loaded, and otherwise sent the text down the message path.

## Decision

A Pi `/` command is staged as a **command chip** at the start of the composer, separate from the text field, which then holds only the command's arguments:

1. Picking a command in the `/` menu (pointer, or arrow keys then Enter or Tab), or typing `/name` followed by a space, stages the chip. A hand-typed `/name` that is sent becomes a chip first; the next send runs it. Text with a `/` but no chip is always a message.
2. Backspace at the start of the empty field, or the chip's close control, removes the chip; without arguments `/name` goes back into the field as text.
3. Pi built-in and extension commands run without a chat entry. Prompt templates and skills still produce a user message, because Pi expands them into one.
4. The chip confirms the mode change with a short pop-in and a one-shot accent glow, and shows a progress indicator while the command runs; under reduced motion it appears without animation.

The user-facing behaviour is described in `docs/user-guide.md` ("Pi slash commands and command chips"), and the chip and menu in `DESIGN.md` (Components).

## Consequences

The composer always shows whether it holds a message or a command, so a command can no longer reach the model as text by accident. The chip and the keyboard-driven slash menu are shared components (`features/composer/command_chip.dart`, `slash_menu.dart`). The chip's gradient fill and glow are the one place where the composer uses those effects; `DESIGN.md` records them as an exception to the anti-slop gate.

## Alternatives Rejected

Colouring command text inside the field (it is still text and can be sent as a message by mistake); a separate command input (it splits the composer and slows frequent use).
