# ADR 0022: One Workspace Window: Sessions Rail, Chat and Companion Panes

- **Status:** Accepted
- **Confirmation Date:** 2026-11-23
- **Stakeholder Decision Reference:** old DESIGN.md design decision log, "Lock Bento Triptych" (2026-10-06) and the D9 live-review revision (2026-10-07)

## Context

PiFrame users follow the agent while they read and edit the session's repository and review its Git changes. Three layouts were explored in October 2026: "Bento Triptych" (repository, chat and Git Changes as co-visible peers), "Artifact Atlas" (editor first) and "Conversation Desk" (chat first, repository and Git behind it). The user chose and locked the Bento Triptych spatial grouping, without copying VS Code's chrome.

## Decision

The app is one window with three related work areas tied to the active session: the sessions rail, the chat pane, and companion panes (repository with the file editor, Git Changes, and the web browser on desktop). The repository and Git Changes panes always follow the active session's working folder. The layout adapts by width instead of hiding a work area:

- 1440 px and wider: every visible pane side by side.
- 900 to 1439 px: the chat pane plus one companion pane, the others as tabs in the companion's header.
- Below 900 px: one pane at a time with a pane selector, chat first.
- The sessions rail is docked only from 1560 px; narrower windows show it as a drawer, so the work panes keep their minimum widths.

Panes are resizable and can be hidden; a companion pane that would get less than 160 px collapses to its tab, and the chat pane never gets narrower than 420 px. "Bento" names this spatial grouping only, not a visual style.

## Consequences

Chat, code and changes stay one step away from each other at every width, and a session switch changes all of them together. Each pane keeps its own state (scroll, selected file, unsaved editor text) when it is hidden or switched. The Agents pane, added later, follows the same rules as a further companion of the chat pane.

## Alternatives Rejected

Artifact Atlas (gives the editor too much weight for an agent workbench); Conversation Desk (hides the repository and Git Changes behind the chat).
