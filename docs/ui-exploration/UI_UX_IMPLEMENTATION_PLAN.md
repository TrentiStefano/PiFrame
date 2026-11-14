# PiFrame — UI/UX Implementation Plan

**Source:** `docs/ui-exploration/UI_UX_REVIEW.md` (the audit, rounds 1–6).
**Audience:** the coding agent that will implement the changes.
**Goal:** bring the app to a professional, consistent finish against its own `DESIGN.md`: closed feedback loops, a code-enforced design system, full keyboard parity, and one coherent motion language.

IDs such as `P1-3`, `N2`, `R1`, `M-8`, `G-2` and `§6.10` refer to the audit. Read the cited audit section before starting a task; it holds the evidence and the screenshots.

---

## 0. How to work through this plan

### 0.1 Rules that apply to every task

1. **Follow `AGENTS.md`.** Real UI captures only, no mock-ups. No invented metrics. Update `docs/install.md` for a new feature and `docs/troubleshooting.md` for an important bug fix.
2. **Follow `DESIGN.md`.** This plan does not introduce a new style. Where this plan and `DESIGN.md` disagree, stop and ask the maintainer.
3. **Line numbers in the audit are approximate.** Several files changed after the audit. Locate code with a search for the symbol or string, not by line number.
4. **Paths.** App code is in `apps/pi_frame/lib/`. The theme package is `packages/pi_frame_theme/lib/src/`. Tests are in `apps/pi_frame/test/`. Unless a path starts with `packages/`, paths in this plan are relative to `apps/pi_frame/lib/`.
5. **Localization.** Every new or changed string goes in `data/language/strings_*.dart` in **both** Italian and English. No string literals in widgets.
6. **Tokens only.** New code uses no literal colour, radius, font size, spacing, duration or curve. Use the tokens from Phase 2. If a token is missing, add it; do not add a literal.
7. **Stable keys.** Give every new interactive control a `ValueKey<String>`, so the harness and tests can reach it.
8. **Tests.** Each task adds or updates widget tests. Do not weaken an existing test to make it pass; if a test encodes the old behaviour, change it and say so in the commit message.
9. **Scope.** One task = one commit. One phase = one branch and one pull request. Do not mix phases.

### 0.2 The verification loop for each task

Use the skill `.agents/skills/piframe-ui-harness/SKILL.md`. It runs an isolated off-screen app with fake-pi and never touches the maintainer's own PiFrame.

1. `pnpm harness start --seed --size 1584x991` (add `--scenario <name>` as each task says).
2. Capture the **before** state: `pnpm harness shot <task-id>-before`.
3. Edit, then `pnpm harness reload` (or `restart` / `rebuild`, as the skill explains).
4. Capture the **after** state and read the PNG. Check it against the task's "Done when" list.
5. Repeat the capture for each of: **dark and light** theme, **1280×720 and 1920×1080**, and **reduced motion on** (`pnpm harness media --reduce-motion on`) when the task touches motion. For layout tasks, also check `--text-scale 1.4`.
6. Check the harness logs for `RenderFlex overflowed` and Flutter exceptions. There must be none.
7. `pnpm harness stop`.
8. Run `flutter analyze` and `flutter test` in `apps/pi_frame`.

Save before/after captures in `docs/ui-exploration/captures-impl/` named `<task-id>-before.png` / `<task-id>-after.png`. Do **not** commit screenshots that tests regenerate in `docs/design-evidence` or `website/assets`; restore them with `git checkout -- <path>`.

### 0.3 Before each pull request

1. Commit the work.
2. Run `pnpm run verify`. Fix every failure.
3. Open the pull request with `pnpm run pr` (never with a plain `git push` + `gh pr create`).
4. The pull request description lists the task IDs done, the audit IDs closed, and the before/after captures.

### 0.4 Already done — do not redo

| Item | Status |
|---|---|
| P0-1 provider-error feedback (`applyTerminalStop`) | Fixed and verified (audit §14.1, §16.1) |
| P1-9 / M-1 activity loops under reduced motion; reduce-motion toggle in Appearance | Fixed (§14.2) |
| `ui/motion.dart`: `FrameMotion`, `FrameEnter`, `FrameExpandable` | Exists; extend it, do not replace it |
| Tool-card and step-group expansion use `FrameExpandable` | Done |
| Composer height tween 240 ms `enterCurve` (M-5) | Done |
| Escape closes Settings; Settings back button has a tooltip and key (P2-3 in part, N8) | Done in round 6 |
| Theme-switch "smear" (M-7) | Not a defect; leave the 240 ms `AnimatedTheme` |

### 0.5 Product decisions (confirmed)

These are product decisions. **The maintainer confirmed every default below on 2026-11-14.** Implement them as written; do not ask again. Items marked "Deferred" are out of scope for this plan.

| # | Decision | Confirmed choice |
|---|---|---|
| D-1 | Show the full triptych from about 1280 px when the session rail is collapsed (P2-19)? | No change to breakpoints. Deferred. |
| D-2 | Settings as a left-nav view (keeps full screen) or as a sheet over the workspace? | Left-nav, full screen, with a compact run-status chip in the Settings header. |
| D-3 | Agents tab: apply immediately, or keep Save/Cancel? | Keep the bar, but show it only when the form is dirty. |
| D-4 | Remove the four legacy built-in themes (P3-8)? | Keep them. Only fix the stale comment. |
| D-5 | Startup assemble overlay on every launch (M-6)? | Play on first run only; add a Settings toggle "Animazione di avvio". |
| D-6 | Activity cues: keep the round 3 design (ring sweep + pulses in normal motion)? | Keep. Do not implement audit Spec D. |
| D-7 | Git discard: confirmation dialog, or recoverable stash with Undo? | Keep the confirmation dialog (fixed per task 1.1). Stash-with-undo is deferred. |
| D-8 | Assistant turn without a border (§6.6)? | Yes, borderless, as D9 round 9 asks for intermediate blocks. |

---

## 1. Phase overview

| Phase | Theme | Audit items | Size |
|---|---|---|---|
| 1 | Safety and trust quick fixes | N2, N3, N5, P1-4, R1, R2, R3, P1-11, P1-12, P2-2, N7, N9, N10, P2-1 | S each |
| 2 | Design-system foundation | P1-13, P1-14, P2-7, P2-8, P2-9, P1-10 (focus ring), P3-1 | L |
| 3 | Git review surface | P1-1, P1-2, P1-3, P2-10, P2-14, P2-15, N6, P3-6 | M–L |
| 4 | Chat transcript and composer | P1-6, P1-7, P2-16, R4, R5, R6, §6.6, §6.7 | M |
| 5 | Sessions, welcome, title bar | P1-15, P2-11, P2-12, P2-13, P2-22, N11–N13 | M |
| 6 | Keyboard and accessibility | P1-10, P1-17, P2-3, P2-4, P2-5, P2-23, N4 | M |
| 7 | Motion system | P1-16, M-2, M-3, M-8, M-9, P2-20, P2-21 | M |
| 8 | Settings | P2-6, §6.15, §6.16, R9 | M |
| 9 | Repository editor | P1-8, §6.9 | M–L |
| 10 | Side conversation, browser, compact, mobile web | P1-5, P2-17, P2-18, §6.11 | M |
| 11 | Polish | P3-2 … P3-11, N14, N15, R7, R8 | S each |
| 12 | Final verification and documentation | — | S |

Phase 1 is independent. Phase 2 must land before Phases 3–11, because they use its tokens and widgets. Phases 3–10 can then run in any order, but only one at a time on files they share (`repository_workspace.dart`, `app_shell.dart`, `composer.dart`, `transcript_view.dart`).

---

## 2. Phase 1 — Safety and trust quick fixes

Small changes with a large effect. No new shared widgets are needed.

### 1.1 Git discard dialog: wording and danger style (N2, N3) — do this first
- **Where:** discard confirmation in `features/workspace/repository_workspace.dart`; strings in `data/language/`. Compare with the delete-session dialog in `features/sessions_sidebar/session_actions.dart`, which is already correct.
- **Steps:**
  1. Rename the destructive button from "Annulla modifiche" to **"Scarta modifiche"** (EN "Discard changes"). The cancel button stays "Annulla".
  2. Style the destructive button with the `danger` token, exactly as the delete-session "Elimina" button.
  3. Move the consequence sentence ("cannot be undone") to the top of the dialog body, above the diff preview.
  4. Apply the same rule to every destructive confirm (package remove, repository remove, extension confirm when the extension marks it destructive): danger fill for the irreversible action, text button for cancel, cancel has initial focus.
- **Done when:** capture of the discard dialog shows "Annulla" (text) and "Scarta modifiche" (danger). Enter does not trigger the destructive action by default. A widget test asserts the labels and the focused button.

### 1.2 Fix every RenderFlex overflow (P1-4, R1, R2)
- **Where:** `features/browser/web_browser_pane.dart` (companion header and toolbar); `features/transcript/todo_panel.dart`; task-notification card and assistant header in `features/transcript/transcript_view.dart`; Agents sidecar / `features/transcript/subagent_panel.dart`; composer chip row in `features/composer/composer.dart`.
- **Steps:**
  1. Reproduce each overflow in the harness: browser companion at default width (captures `25`–`27`, `30`); scenarios `todos`, `ui-status-widgets`, `subagents`; drag the divider to make the chat pane about 300 px wide.
  2. Browser: collapse the toolbar to one row (back, forward, reload, address field as `Expanded`, overflow menu). Below 360 px, move home, star and extensions into the overflow menu. Remove the quick-link chip row under the toolbar (the home page grid already shows them).
  3. Transcript headers and cards: wrap text in `Flexible`/`Expanded` with ellipsis; let trailing controls keep their intrinsic size. Do not use fixed widths.
  4. Agents sidecar: give the chat pane a minimum width of 420 px. When the pane would be narrower, show the sidecar as an overlay sheet inside the chat pane instead of squeezing it.
  5. Composer chips: on overflow, truncate the model name first, then drop chip labels to icon + tooltip. Chips must never overlap.
  6. Give companions a minimum width of 320 px in `app/app_shell.dart` (today only a 15 % weight floor applies). Below that width the pane collapses to its tab.
- **Done when:** no overflow stripe or log line at 680, 900, 1280, 1440 and 1920 px wide, with every pane combination and the Agents sidecar open. Add a widget test that pumps each fixed widget at 280 px and 320 px and expects no exception.

### 1.3 Git group header overlaps the summary line (N5)
- **Where:** Git list in `features/workspace/repository_workspace.dart`.
- **Steps:** keep the summary line ("207 file +74626 −9") outside the scroll view, or make the group headers sticky below it with an opaque background. Clip the scroll area.
- **Done when:** with the seeded 200-file fixture, scrolling never draws text over the summary line, in dark and light.

### 1.4 Startup update banner covers the composer (R3)
- **Where:** `features/updates/startup_update_banner.dart` and where the shell places it.
- **Steps:** anchor the banner at the top-right under the title bar (or render it as an inline row at the top of the sessions rail). It must not overlap the composer. Remove `elevation: 8`; use a 1 px border on `surfaceElevated`.
- **Done when:** scenarios `provider-error` and `edit-files` show model, thinking and send controls fully visible with the banner present.

### 1.5 Packages tab: labelled loading, timeout, error (P1-11)
- **Where:** `features/settings/settings_view.dart` (packages section).
- **Steps:**
  1. Replace the lone spinner with 4 skeleton rows and the text "Caricamento pacchetti…".
  2. After 10 s without a result, show "Il caricamento richiede più tempo del previsto" with **Riprova**.
  3. On failure, show a callout with a localized message, **Riprova**, and a collapsible "Dettagli" with the raw error.
- **Done when:** the three states are covered by a widget test with a fake controller, and each is captured.

### 1.6 Map raw exceptions to user messages (P1-12)
- **Where:** new `domain/errors/user_facing_error.dart`; call sites in `features/workspace/repository_workspace.dart` (Git status, branch, file listing), `features/settings/settings_view.dart` (packages), and any other place that shows `error.toString()` or `'$error'` in a widget. The search `(error|e)\.toString\(\)` finds about 54 candidates in `lib/`; review each.
- **Steps:**
  1. Add `UserFacingError { String title; String? hint; String details; }` and a function `describeError(Object error, FrameStrings s)` that maps known failures (daemon unreachable, unsupported command, Git not installed, not a repository, permission denied, timeout, network) to localized title + hint. Unknown errors get "Operazione non riuscita" and keep the raw text in `details`.
  2. Replace each UI use of a raw error with the title and hint, a **Riprova** action when the operation can be retried, and a "Dettagli" disclosure for `details`.
  3. Leave logging unchanged.
- **Done when:** no widget shows `Bad state:` or `Exception:` text outside a "Dettagli" block. A unit test covers each mapping.

### 1.7 Remove internal jargon; finish localization (P2-2, N7)
- **Where:** `data/language/strings_settings.dart` (the `(D9)` and `D16` strings near lines 99, 238, 784) and the other `strings_*.dart` files.
- **Steps:**
  1. Delete "(D9)", "D16" and "(D16)" from user copy; rephrase the sentence so it still reads well.
  2. Translate the English fragments in the Italian UI: `CONNECTED`, "No subagent package installed", "untracked · unstaged", "Side · read-only", "Reasoning about problem…", slash-menu descriptions and the "builtin" source label (use `Pi` / `estensione` / `prompt` / `skill`, as `DESIGN.md` §08 says).
  3. Remove bilingual parentheticals: "Duplica ramo", "Albero dei rami".
  4. Thinking levels: "Spento / Basso / Medio / Alto" (EN "Off / Low / Medium / High"), not raw enum names.
  5. Use sentence case for labels ("Nuova sessione", not "Nuova Sessione").
- **Done when:** a test scans the Italian strings for the patterns `\(D\d+\)`, `\bD16\b` and a short deny-list of English words, and passes.

### 1.8 Semantic colour corrections (P2-1, N10)
- **Where:** `features/settings/settings_view.dart` (tab indicator, MCP card), `features/settings/remote_section.dart` (callout), `features/side/side_panel.dart` (tag), session header context chip in `features/transcript/transcript_view.dart`, read-tool icon in `features/tool_timeline/tool_card.dart`, MCP dialog icon tile in `features/dialogs/`.
- **Steps:** Settings tab indicator → `accent`. MCP card and "Gestisci" → neutral. "Side · read-only" tag → neutral/info. Remote "missing binary" callout → info while remote access is off, warning only when it is on. Context icon → muted below 70 % usage, `warning` from 70 %, `danger` from 90 % (or at the compaction margin if that is lower). Read-tool icon → muted or `info`; red only for a failed tool.
- **Done when:** in captures of Settings, Remote, Side and a transcript with successful reads, warning and danger colours appear only where something needs attention.

### 1.9 Crash-recovery composer (N9)
- **Where:** `features/composer/composer.dart`, scenario for a stopped worker (see `pnpm harness scenarios`).
- **Steps:** hide the stop button when no run is active. Give the remaining actions text labels ("Riavvia", "Reinvia"). Fix the banner so it wraps on word boundaries.
- **Done when:** the capture after "Worker arrestato" shows only actions that do something, each with a label.

---

## 3. Phase 2 — Design-system foundation

This phase turns `DESIGN.md` §07 into code. It is the base for all later phases.

Measured baseline in `apps/pi_frame/lib/` on the plan date:

| Literal | Count |
|---|---:|
| `fontSize:` numeric literals | 715 |
| of which below 11 px | 130 |
| `BorderRadius.circular(<number>)` | 50 |
| `Duration(milliseconds: <number>)` | 47 |
| `Curves.*` | 27 |
| `BoxShadow(` | 16 |
| `GestureDetector(` | 14 |
| `FocusTraversalGroup` | 0 |

### 2.1 Spacing, type, size and motion tokens
- **Where:** `packages/pi_frame_theme/lib/src/theme_tokens.dart`, `theme_spec.dart`; `ui/motion.dart`.
- **Steps:**
  1. **Spacing:** add `FrameSpace` constants `x1=4, x2=8, x3=12, x4=16, x6=24, x8=32`. These do not vary by theme, so plain constants are enough.
  2. **Type:** add named text roles built from the theme's font families: `caption 11/16`, `label 12/16`, `body 13/20`, `bodyLarge 14/20`, `title 16/22`, `heading 20/26`, `display 28/32`, plus `mono 12/18` and `monoBody 13/20` (size/line-height in px). Expose them as a `ThemeExtension` or via `TextTheme`, reachable with one call such as `FrameText.of(context).label`. 11 px is the floor.
  3. **Sizes:** `FrameSize.rowList = 28`, `rowForm = 40`, `hitMin = 28`, `icon = 16`, `iconLg = 20`, `paneHeader = 40`.
  4. **Motion:** extend `FrameMotion` with `instant` (zero), `smallExit` 120 ms, `panelExit` 180 ms, `dialog` 180 ms, `dialogExit` 120 ms, `firstRun` 300 ms, `stagger` 100 ms. `FrameTokens` also has `pressDuration`, `panelDuration`, `enterCurve` and `panelCurve`; keep one source of truth (make `FrameMotion` read the same constants) so the two cannot drift.
  5. **Borders:** add an `inputBorder` colour token with at least 3:1 contrast against `surface` in both official themes (P2-8). Use it for text fields, the composer and search fields. Compartment borders keep the quiet `border` token.
  6. Extend `test/design_tokens_test.dart` for the new tokens, including a contrast assertion for `inputBorder` and `focusRing` (≥3:1).
- **Done when:** tokens exist, are documented in `docs/theming.md`, and tests pass.

### 2.2 Visible focus ring (P1-10, first half)
- **Where:** `packages/pi_frame_theme/lib/src/theme_spec.dart` (today `focusRing` is used only for the input border); new `ui/frame_focus.dart`.
- **Steps:**
  1. Add `FrameFocusRing`: a wrapper that draws a 2 px `focusRing` outline with a 2 px offset and the child's radius, **only** when focus was reached by keyboard (`FocusManager.instance.highlightMode == FocusHighlightMode.traditional`).
  2. In `ThemeData`, set the focused state for `IconButton`, `TextButton`, `FilledButton`, `OutlinedButton`, `Switch`, `Checkbox`, `Tab`, `ListTile` and menu items so that focus shows a `focusRing` side or overlay that differs from hover.
  3. Soften the command-palette search focus outline to the same ring (the audit calls the current one heavy).
- **Done when:** repeat the audit's 8-step Tab capture (`captures-r2/r2-12`–`r2-19`); every step shows a crisp ring, in dark and light. Mouse clicks show no ring.

### 2.3 Shared primitives in `lib/ui/` (P1-14)
Create these widgets, each with a widget test and with keyboard focus, hover, pressed, selected and disabled states built in:

| Widget | File | Contract |
|---|---|---|
| `FramePaneHeader` | `ui/frame_pane_header.dart` | 40 px. Title in the pane-heading style, optional subtitle/path, trailing actions, optional tab strip. Flat: no inner card. |
| `FrameIconAction` | `ui/frame_icon_action.dart` | 16 px glyph in a 28×28 target. **Requires** a tooltip (which is also the semantic label) and takes an optional shortcut shown in the tooltip. |
| `FrameListRow` | `ui/frame_list_row.dart` | Min height 28 px (not fixed). Leading icon, **name** in primary text, secondary text muted with middle ellipsis, trailing badge, hover/focus-revealed actions that stay reachable by Tab, `selected` state, `onTap`, `onSecondaryTap` for a context menu. |
| `FrameStatusTag` | `ui/frame_status_tag.dart` | Dot + label, tones neutral / info / success / warning / danger. Never full width. |
| `FrameSection` | `ui/frame_section.dart` | Settings and dialog section: title, optional description, 16 px padding, one border level. |
| `FrameCallout` | `ui/frame_callout.dart` | Tones info / warning / danger. Title, body, optional action, optional "Dettagli" disclosure. |
| `FrameEmptyState` | `ui/frame_empty_state.dart` | Icon, title, one sentence, **one action button**, optional shortcut hint. |
| `FrameSearchField` | `ui/frame_search_field.dart` | One border (`inputBorder`), 32 px, clear button, Escape clears then unfocuses. |
| `FrameDialog` | `ui/frame_dialog.dart` | Title in one heading style, body, actions right-aligned (cancel = text, primary = filled, destructive = danger). Height fits content up to 80 % of the window. Uses the `dialog` motion token (Phase 7). |
| `FrameMiddleEllipsis` | `ui/frame_middle_ellipsis.dart` | Truncates a path in the middle and keeps the last segment whole. Shows a tooltip only when the text is actually truncated (N14). |

Add `ui/frame_press.dart` only if `ui/precision.dart` cannot be reused: press scale 0.97 / 120 ms on **buttons**, never on rows or disabled controls.

### 2.4 Button and heading rules
- **Buttons:** one filled primary per view or dialog. Secondary = outlined neutral. Passive "Chiudi" = text button. Destructive = danger. Apply to Pi CLI ("Esegui" buttons: all outlined; mark the recommended one with a "Consigliato" tag), session tree, MCP manager, editor "Salva".
- **Headings:** Barlow Condensed only for the brand and for pane headings in `FramePaneHeader`. Dialog titles, Settings section titles and the session title use the Schibsted `title`/`heading` roles.
- **Switches:** off state uses the `border` token for its outline, so it is quieter than the on state (P3-4).
- **Elevation:** remove `BoxShadow` and `elevation` from the attachment chips, the sessions surface and the side panel. Keep a shadow only on true overlays (menus, dialogs, drawers).
- **Icons (P3-1):** use the outlined Material variant everywhere; sizes 16 or 20 only. Change the `.gitignore` file icon to a neutral colour.

### 2.5 Migrate literals and add a ratchet test
- **Steps:**
  1. Migrate one feature folder per commit, in this order: `tool_timeline`, `transcript`, `workspace`, `sessions_sidebar`, `composer`, `settings`, `browser`, `side`, `context_panel`, `dialogs`, `command_palette`, `session_changes`, `session_tree`, `status`, `updates`, `metrics`, `ui/code`.
  2. Replace font sizes with the type roles (everything below 11 px becomes `caption`), radii with `radiusSm/Md/Lg/Pill`, gaps and paddings with `FrameSpace`, durations and curves with `FrameMotion`.
  3. Replace feature-local headers, chips, rows, empty states and callouts with the Phase 2.3 widgets where the swap is mechanical. Larger redesigns belong to later phases.
  4. Add `test/design_literals_lint_test.dart`, modelled on `test/telemetry_lint_test.dart`. It counts the literal patterns in the table above and fails when a count is **higher** than a baseline stored in the test. Lower the baseline in each migration commit. Allow-list `packages/pi_frame_theme` and `ui/motion.dart`.
  5. After each folder, capture the affected screens and compare with the before captures. Sizes below 11 px will grow; fix any layout that breaks.
- **Done when:** counts reach these targets: font sizes below 11 px = 0; `fontSize:` literals ≤ 20 (documented exceptions only); numeric radii = 0; duration and curve literals = 0 outside `ui/motion.dart` and the startup animation; the ratchet test is in place.

### 2.6 Hit targets (P2-9)
- Raise every interactive target to at least 28×28 px (24×24 is the hard minimum): folder "new session" button in `sessions_sidebar.dart`, Git row actions, chip remove, tree-dialog close. `FrameIconAction` enforces this for new code.

---

## 4. Phase 3 — Git review surface

The weakest of the three Bento pillars today. Files: `features/workspace/repository_workspace.dart`, `features/session_changes/`, `ui/code/diff_block.dart`. `repository_workspace.dart` is about 3,700 lines; start by extracting the Git list, Git row, diff view and commit form into their own files under `features/workspace/git/` with no behaviour change, in one commit.

### 3.1 Filename-first, single-line rows (P1-1, P1-2, N6)
- **Steps:**
  1. Build rows with `FrameListRow`: file icon, **file name** in primary text, parent directory in muted text with `FrameMiddleEllipsis`, a 16 px status badge (M / A / D / R / U, mono 11 px, coloured by status), then actions. Reuse the layout of the `@`-mention menu in the composer, which already does name-then-path.
  2. Row height 28 px, group header 28 px. Remove the second meta line. Show provenance (agent / manual) as a small icon with a tooltip, and only when it is known.
  3. Stage (+), unstage (−) and discard appear on hover or focus, stay reachable by Tab, and are 28 px targets. Put a gap of at least 8 px between stage and discard.
  4. Expand the CHANGES group by default when it has files; expand STAGED when it has files and CHANGES is empty.
- **Done when:** at a 380 px pane width every row shows the complete file name; twice as many rows are visible as in capture `43`; no text is under 11 px.

### 3.2 Diff inside the companion pane (P1-3, motion Spec B)
- **Steps:**
  1. Replace the modal diff with an in-pane view. Selecting a row swaps the companion body from the list to the diff. Chat stays visible.
  2. Diff header (`FramePaneHeader`): back button "← Modifiche", file name, position "2/5", previous / next file, Stage or Unstage, Scarta…
  3. Keys: Enter opens, Escape or Alt+← goes back, Alt+↓ / Alt+↑ moves to the next / previous file.
  4. Transition: outgoing list fades out and moves −8 px on x; incoming diff fades in from +8 px. 180 ms in, 120 ms back, `enterCurve`. Keyboard file-to-file navigation is instant. Reduced motion: 120 ms cross-fade.
  5. In the compact layout (<900 px) the diff takes the full pane with the same header.
  6. Keep an "Apri in finestra" action that opens the old large view for wide diffs, built with `FrameDialog` and sized to content.
- **Done when:** the audit sequence `42→43→44` can be repeated with the chat visible throughout, and the maintainer can review five files using only the keyboard.

### 3.3 Empty and loading states (P2-10)
- Clean tree: `FrameEmptyState` "Nessuna modifica" with the current branch and a "Aggiorna" action. Not a Git repository: explain, with "Inizializza repository" only if that action already exists; otherwise no button. Loading: three skeleton rows plus "Lettura stato Git…".

### 3.4 "Writes disabled" banner without layout shift (P2-15)
- Reserve the space, or render the state as a compact inline line in the action bar ("Scritture sospese mentre Pi lavora") in place of the Fetch/Pull/Push/Sync buttons' enabled state. The list must not move when a run starts or ends.

### 3.5 Commit form (P2-14)
- Two fields: subject (single line, soft guide at 72 characters with a counter that turns `warning` past it) and optional body (multiline). **Commit** is disabled until the subject is non-empty. Ctrl/Cmd+Enter commits. Show the result as a success snackbar with the short hash, or a `FrameCallout` on failure (through `describeError`).

### 3.6 Context menu and keyboard (P3-6)
- Right-click on a Git row: Apri diff, Stage / Unstage, Scarta…, Copia percorso, Aggiungi alla chat. Keys on the focused row: ↑/↓ move, Enter opens the diff, Space stages or unstages, Delete opens the discard confirmation.

### 3.7 Compact / mobile action bar
- In the compact layout, Commit spans the full width under the four equal Fetch/Pull/Push/Sync buttons (audit §6.10 item 9).

---

## 5. Phase 4 — Chat transcript and composer

Files: `features/transcript/transcript_view.dart`, `steps_group.dart`, `thinking_block.dart`, `rich_content.dart`, `features/composer/composer.dart`, `features/tool_timeline/tool_card.dart`.

### 4.1 One geometry for streaming and settled turns (P1-7, D-8)
- **Steps:**
  1. Render the assistant turn as plain content on the pane surface, without a border. Keep the user turn as a tinted block.
  2. Give every assistant turn a 24 px meta line (role label, elapsed time, copy) that is laid out **from the first token**. While streaming it shows the live timer; when settled it shows the final time and the actions. Its height and position never change.
  3. Reveal the actions (copy, "Riparti da qui") on hover or focus; they stay reachable by Tab. "Riparti da qui" is no longer always visible on user messages.
  4. Constrain the reading measure to about 760 px, centred in wide chat panes.
- **Done when:** with scenario `slow-stream`, a capture taken mid-stream and one taken after completion have the turn's first text line at the same y position. Add a widget test that compares the two layouts.

### 4.2 Borderless step group (§6.6 item 1)
- Render "Completato n passaggi" as a 28 px summary row like the tool row, with the same chevron and `FrameExpandable` behaviour. No card border.

### 4.3 Composer stays visible while streaming (P1-6)
- **Steps:**
  1. Remove the collapse-to-a-status-line behaviour for the unfocused composer. The field is always visible.
  2. Add a 28 px status line **above** the field while Pi runs: spinner, "L'agente sta rispondendo…", elapsed time, **Interrompi**. It enters with a 150 ms fade and 4 px rise and leaves in 120 ms. Reserve no space when idle, but the transcript bottom padding must absorb the change so the last message does not jump.
  3. Placeholder while running: "Invio per indirizzare · Alt+Invio per accodare" (check the actual key bindings in `composer.dart` and use the real ones).
  4. Update `test/composer_minimize_animation_test.dart` and related tests to the new behaviour.
- **Done when:** during a run, a keyboard-only user can Tab to the field, type and steer without hovering.

### 4.4 Composer controls (§6.7 items 3–5)
- Thinking picker: localized levels with a 4-step bar icon showing the level. Review button: text label "Rivedi modifiche (n)" when changes exist; when none exist, show it disabled with a tooltip that explains when it becomes available. Compact width: truncate the model name instead of hiding it.

### 4.5 Session header as a flat pane header (P2-16, P2-11 in part)
- Use `FramePaneHeader`: title · cwd (mono, muted, middle ellipsis) · status tag on one 48 px line, metric chips right-aligned. No inner card. Context chip shows "12k / 128k (1.2%)", or "— / 128k" when usage is unknown. Clicking a metric chip opens the context drawer. Double-click the title to rename. Extension status text truncates with a tooltip (R8).

### 4.6 Empty chat (P2-10)
- `FrameEmptyState` in the transcript: cwd and branch, two or three hints ("/ per i comandi", "@ per allegare un file", Ctrl/Cmd+K), and focus goes to the composer.

### 4.7 Content correctness (R4, R5, R6)
- R4: render Markdown tables as tables (horizontal scroll inside the block when wide) and fix the image block for valid PNG data. Scenario `rich-content`.
- R5: mark an aborted turn with a neutral "Interrotto" tag in its meta line.
- R6: the elapsed-time chip ignores predecessors that are not user/assistant messages and shows nothing for values above 24 h.

---

## 6. Phase 5 — Sessions, welcome and title bar

Files: `features/sessions_sidebar/sessions_sidebar.dart`, `session_actions.dart`, `app/app_shell.dart`, `features/context_panel/`, `features/dialogs/`, `features/session_tree/`.

### 5.1 Sessions rail (P1-15, N11, N12, N13)
1. Expand the active repository by default. While a search is active, expand every repository with a match.
2. Session rows with `FrameListRow` at 32 px, indented 20 px: status dot, title, relative time ("2 h fa") right-aligned. Running sessions show the existing pulse (static ring under reduced motion).
3. Provisional title = the first user prompt, truncated to about 60 characters, until the user renames or Pi supplies a title. No timestamp titles; "Nuova sessione" only before the first prompt.
4. Filter control: left-aligned segmented control with a clear selected state and a full-width divider below.
5. Remove the second search icon in the footer.
6. Session context menu holds session actions only (rename, pin, duplicate, delete). Move "Rimuovi repository dal riquadro" to the repository row menu. Use the token border for the menu divider.
7. Keyboard: ↑/↓ move, →/← expand/collapse, Enter opens, F2 renames. Keyboard expand is instant; pointer expand uses `FrameExpandable`.
- **Done when:** switching to another session of the active repository takes one click from a fresh launch.

### 5.2 Welcome as a resume surface (P2-12, P3-10)
- Headline 40–48 px ("Riprendi il lavoro"). Left column (max 560 px): description, **Nuova sessione** (primary), **Esplora sessioni** (secondary), shortcut hint. Right column on wide windows (below the actions on narrow ones): up to 8 recent sessions grouped by repository, as `FrameListRow`s, with ↑/↓ and Enter. Hide the keyboard hint when there is no hardware keyboard (touch / mobile web). Use the same logo treatment on desktop and mobile.
- First-run only: stagger title, description and actions by 100 ms, each 300 ms ease-out with a 12 px rise; cross-fade under reduced motion.

### 5.3 New-session dialog (P2-13)
- The welcome button stays idle until **Crea** is pressed (today it shows "Creazione…" while the dialog is open). Neutral placeholder "Percorso della cartella…". Folder picker as an icon button in the field suffix. Up to 5 recent folders as selectable rows. Validation with a 300 ms debounce: "Cartella non trovata" or "Repository Git rilevato · main". Autofocus, Enter creates when valid, Escape cancels. Build with `FrameDialog`, 480 px wide.

### 5.4 Title bar (P2-11, §6.1)
- Two icon groups separated by a 1 px divider: *Vista* (layout, theme) and *Area di lavoro* (context drawer, settings). Replace the sliders glyph for the context drawer with a labelled button "Sessione" at ≥1100 px, icon-only below. All use `FrameIconAction` with tooltips that include the shortcut. Connection indicator: dot + label at ≥920 px, **dot only with tooltip and semantic label below 920 px** (today it disappears). Clicking it opens Diagnostics.

### 5.5 Context drawer (P2-22)
- One heading "Sessione · <title>". Three sections with 24 px gaps: *Modello*, *Contesto*, *Rami*. Remove the contradictory "Dati non disponibili" when a percentage is shown. "Compatta contesto" is the one primary action in *Contesto*. Close the drawer before a dialog launched from it opens. Session tree dialog shows the session title; the raw ID moves to a copyable detail row.

### 5.6 Session tree and MCP dialogs (§6.14, R7)
- Rebuild both on `FrameDialog`: height fits content, refresh in the header, "Chiudi" as a text button, neutral icon tile, tooltips on every icon. Empty states get one action each ("Apri file di configurazione" for MCP). Session tree: indent children under their parent with connector lines so forks read as a tree.

---

## 7. Phase 6 — Keyboard and accessibility

### 6.1 Focusable custom controls (P1-10)
- Review all 14 `GestureDetector` uses. Replace interactive ones with `InkWell`, `FrameIconAction` or `FocusableActionDetector`, with `Semantics(button: true, label: …)`. Known cases: companion tabs in `repository_workspace.dart` and `session_changes_pane.dart`, the chip remove button in `features/composer/command_chip.dart`, inline file links in `features/transcript/rich_content.dart`. Tabs also get `Semantics(selected: …)` and ←/→ navigation.

### 6.2 Ordered focus traversal (P1-17 / N1)
- Wrap each region in a `FocusTraversalGroup` with `OrderedTraversalPolicy`, in this order: title bar → sessions rail → repository pane → chat transcript → composer → companion pane. Inside a pane, order is top to bottom. Lists are a single Tab stop; arrow keys move inside them.
- Add F6 / Shift+F6 to move focus between panes, and Ctrl/Cmd+1…4 to focus sessions, repository, chat and companion.
- **Done when:** a widget test sends Tab repeatedly from the composer and asserts the region order; the 8-step capture sequence is repeated and is predictable.

### 6.3 Uniform Escape (P2-3)
- Rule: Escape closes the topmost layer, in this order: menu/popover → dialog → drawer → in-pane diff → Review mode → Settings. Only when nothing is open and the composer has focus during a run does Escape interrupt the agent. Implement with one shell-level `Shortcuts`/`Actions` handler in `app/app_shell.dart` and remove ad-hoc handlers that conflict. Add Escape to Review mode (`features/session_changes/session_changes_pane.dart`) and to the end drawer.

### 6.4 Shortcuts (P2-23)
- Add: Ctrl/Cmd+N new session, Ctrl/Cmd+, settings, Ctrl/Cmd+S save in the editor, Ctrl/Cmd+B toggle sessions rail, Ctrl+Tab previous session. First check each against existing bindings and the terminal's keys; when a binding conflicts, keep the existing one and report it. List all shortcuts in `docs/install.md`.

### 6.5 Command palette (P2-5, N4)
- File: `features/command_palette/command_palette.dart`.
  1. Shortcut hints as right-aligned key caps, removed from the command titles. Platform-aware: ⌘ on macOS, Ctrl elsewhere.
  2. Groups: Sessione, Vista, Git, Impostazioni. Add the missing commands: Review Changes, show/hide each pane, focus pane, switch theme, new terminal, Git fetch/pull/push/commit, open each Settings section, and "Vai a sessione…" with fuzzy search over sessions.
  3. Hide commands that do not apply (no "Interrompi agente" when nothing runs).
  4. Close the palette **before** running the chosen command, so it never stays behind a dialog.
  5. List height fits content, max 60 % of the window. Keep it instant (no animation).
- Branch picker: same list sizing; fixed column grid for branch, remote and ahead/behind.

### 6.6 Persist the layout (P2-4)
- `data/layout/layout_store.dart`: also save pane weights, collapsed panes, the compact selected pane and the companion tab. Restore on start; clamp restored weights to the minimum widths from task 1.2. Extend `test/layout_persistence_test.dart`. Then correct the persistence statement in `docs/ui-exploration/NAVIGATION-MAP.md`.

### 6.7 Divider keyboard access
- Give every pane divider the same `Semantics.onIncrease/onDecrease` and ←/→ handling that the sidebar divider already has.

---

## 8. Phase 7 — Motion system

One language: motion explains where things come from and go. Keyboard-initiated and high-frequency actions are instant. Exits are shorter than entrances. Under reduced motion every transition is an opacity cross-fade of at most 150 ms with no movement, and loops are static.

### 7.1 Token table (final)

| Token | Enter | Exit | Curve | Use |
|---|---:|---:|---|---|
| `instant` | 0 | 0 | — | Keyboard-launched overlays, tab switches, tree expand by key |
| `micro` | 120 ms | 120 ms | `enterCurve` | Hover/press colour, selection, status cross-fade |
| `small` | 160 ms | 120 ms | `enterCurve` | Expand/collapse, chips, menus, row enter |
| `panel` | 240 ms | 180 ms | `panelCurve` | Pane show/hide, side panel, drawers |
| `dialog` | 180 ms | 120 ms | `enterCurve` | Click-launched dialogs: opacity + scale 0.97→1 |
| `firstRun` | 300 ms + 100 ms stagger | — | ease-out | Welcome first run and empty states only |

### 7.2 Helpers to add in `ui/motion.dart`
- `FrameSwitcher`: an `AnimatedSwitcher` preset (fade + optional 8 px directional slide, exit shorter than enter, reduced-motion aware). Use it for the list ↔ diff swap, companion tab content, Settings content and composer control swaps.
- `showFrameDialog`: wraps `showGeneralDialog` with the `dialog` token and an `instant` option for keyboard-launched overlays.
- `FrameExpandable`: add the shorter collapse duration (`smallExit`) and an `animate: false` option for keyboard-initiated toggles.

### 7.3 Pane show / hide / collapse with animated width (P1-16, Spec A)
- **Where:** pane layout in `app/app_shell.dart`.
- **Steps:** animate the flex weights with one `AnimationController` (240 ms show, 180 ms hide, `panelCurve`). Lay the entering pane out at its **final** width inside a `ClipRect` so its content does not reflow during the animation; fade its content in after 60 % of the travel. Neighbours move with the weights. Divider drags and keyboard-initiated toggles are instant. Review-mode entry and exit use the same transition. Wrap each pane in a `RepaintBoundary`.
- **Done when:** toggling a pane from the title bar shows a smooth width change with no text reflow and no dropped frames in profile mode; with reduced motion it is a 150 ms cross-fade at the final layout. Update `test/pane_collapsing_test.dart`.

### 7.4 Stage / unstage row travel (Spec F)
- Row leaves the source group with opacity 1→0 and y 0→−4 px in 120 ms, then appears in the target group with opacity 0→1 and y 4→0 px in 160 ms. Group counts update at once. Reduced motion: instant.

### 7.5 Dialogs (M-8)
- Move every click-launched dialog to `showFrameDialog`. The command palette, branch picker, slash menu and every overlay opened by a shortcut stay instant.

### 7.6 Snackbar and inline errors (Spec G)
- `ui/frame_snack_bar.dart`: enter with opacity + 8 px rise in 180 ms, exit with opacity in 120 ms. Success auto-dismisses after 4 s. Errors stay until dismissed and have a ✕. Errors are announced through `SemanticsService.announce`.

### 7.7 Remaining gaps (M-3, M-9, inventory in audit §10)
- Add reduced-motion handling and token timings to: chip hover/remove (colour change only; remove the ✕ rotation), drop-target overlay (200 ms in, 120 ms out), todo/activity overlay size, subagent panel size and row enter (add an exit), companion tab indicator.

### 7.8 Startup overlay (P2-20, D-5)
- Play the 1.4 s assemble animation and its audio on the first run only. Add a toggle in Appearance. Later launches use the 620 ms launch reveal. Update `test/startup_animation_and_window_test.dart`.

### 7.9 Press feedback
- Apply the existing 0.97 / 120 ms press scale to all filled and outlined buttons through the theme or `FrameIconAction`. Never to rows, tabs or disabled controls.

### 7.10 Verification
- Extend `test/motion_reduced_test.dart`: each helper in both modes. Take paired captures in normal and reduced motion for: pane toggle, diff open, side panel, dialog, expand/collapse, stage. Compare two frames about 1 s apart during a run to confirm that the session dot and subagent pulse are static under reduced motion (still **not verified** in the audit, §16.1).

---

## 9. Phase 8 — Settings

Files: `features/settings/settings_view.dart` (about 2,300 lines), `remote_section.dart`. First split the file: one file per section under `features/settings/sections/`, no behaviour change, one commit.

### 8.1 Shell (§6.15, D-2)
- ≥900 px: left vertical nav, 220 px, three groups — *Generale* (Aspetto, Terminale, Aggiornamenti, Privacy), *Pi* (Pi CLI, Pacchetti, Agenti), *Sistema* (Daemon, Diagnostica, Accesso remoto). Sentence-case labels, accent selection bar, ↑/↓ navigation. Content column max 760 px, 32 px between sections.
- <900 px: a scrollable tab row with fade edges that show there is more.
- Header shows a compact run-status chip for the active session, so a running agent stays visible.
- Content switch: 120 ms cross-fade for pointer, instant for keyboard.

### 8.2 One section grammar
- Every card is a `FrameSection`. Every status is a `FrameStatusTag` (replace the full-width `CONNECTED` / `DISABILITATA` bars). Every form field is 40 px high. Remote cards use the same inset and border as the rest. One status vocabulary for the daemon across Daemon and Diagnostica.

### 8.3 Per-section changes (audit §6.16)
| Section | Change |
|---|---|
| Pi CLI | One card style; "Consigliato" tag instead of coloured borders. When a command runs, scroll the output console into view; on wide windows place the console in a right column. |
| Pacchetti | Done in task 1.5; move onto `FrameSection` / `FrameListRow`. |
| Daemon | Explain the restart consequence under the button ("Le sessioni in corso verranno riconnesse") and confirm before restarting while a run is active. |
| Aspetto | One "Tema" control: Sistema / Chiaro / Scuro. Show "Tema chiaro" and "Tema scuro" selects only as needed (both for Sistema, one otherwise). Remove the info box that repeats the selection. Rename "Statistiche nerd" to a neutral label (e.g. "Statistiche tecniche") — confirm wording with the maintainer. |
| Privacy | Merge into Diagnostica as a short section; keep the nav entry only if content remains. |
| Terminale | Disable the native-terminal list until "nativo" is selected. |
| Accesso remoto | Callout tone per task 1.8; install button as secondary; port in muted mono text. |
| Agenti | Save bar only when dirty (D-3). One empty state with the action "Apri Pacchetti". Show "Predefinito di Pi: <model>" instead of "—". Investigate R9: the model selects are empty although the model query returns models. |
| Editor tema | Token border for the separator. Preview built from real components (pane header, Git row, chat turn). Token search field. Explain or remove the "In corso" tag. |

---

## 10. Phase 9 — Repository editor

Files: editor part of `features/workspace/repository_workspace.dart`, `ui/code/code_editor_controller.dart`, `ui/code/syntax_highlighter.dart`. Extract the editor into `features/workspace/editor/` first.

### 9.1 Code-grade editor surface (P1-8)
1. Source Code Pro, 13 px / 20 px line height, for **all** file types in source mode, Markdown included. No link styling in source mode.
2. Line-number gutter, 44 px, muted, right-aligned; it must stay aligned with wrapped lines.
3. Wrap off by default for code, on for Markdown and plain text; the toggle stays.
4. Current-line highlight with a subtle `surfaceElevated` band.
5. Selection → context menu → "Aggiungi alla chat (file:L10–L24)" with the real line range (D9 round 2 asked for this).
6. Ctrl/Cmd+G "Vai alla riga".
- **Done when:** capture `27` repeated shows mono text with line numbers; a widget test checks the gutter count against the line count and the line range passed to add-to-chat.

### 9.2 Save and dirty state
- "Salva" is a text button when clean and filled when dirty; the file name shows "●" when dirty. Ctrl/Cmd+S saves. Closing the editor or switching session with unsaved changes asks: Salva / Non salvare / Annulla.

### 9.3 Tree and header (P3-3, P3-6, P3-11)
- Add-to-chat appears on row hover or focus and in the context menu. Folder context menu: Nuova sessione qui, Copia percorso, Aggiungi cartella alla chat. Tree rows use min-height 28 px, not a fixed height. Search uses `FrameSearchField` (single border). Header and terminal icons use `FrameIconAction`; group the less common ones (collapse all, expand all) in an overflow menu.

---

## 11. Phase 10 — Side conversation, browser, compact, mobile web

### 10.1 Side conversation as a true split (P1-5, Spec C)
- **Where:** `features/side/side_panel.dart` and the chat pane in `app/app_shell.dart`.
- **Steps:** place the side panel in a `Row` with the main chat, 40 % wide, with a draggable divider (min 320 px each side). When the chat pane is narrower than 720 px, show the side conversation as a full-pane view with a back button instead. Remove the drop shadow. Reuse the composer in compact mode for its input. Ask for confirmation on close only when a side draft exists. Escape closes it (through task 6.3).
- **Motion:** width 0→40 % in 240 ms, close in 180 ms, `panelCurve`; content fades in after 50 %. Ctrl+Shift+B is instant. Reduced motion: 150 ms cross-fade.
- **Done when:** capture `30` repeated shows the main chat fully readable beside the side thread, with no clipped text.

### 10.2 Browser companion (§6.11)
- After task 1.2: move the browser tab strip into the companion title bar (`FramePaneHeader` tab strip), so content starts after two rows, not three.

### 10.3 Compact layout (P2-17)
- Selected tab: accent text plus a 2 px accent underline and `Semantics(selected: true)`. Remove the duplicate pane title under the tab in compact mode; keep the pane actions. Show run status in the tab label ("Chat ●" with a semantic label).

### 10.4 Mobile web (P2-18)
- Load the bundled fonts before the unpaired and offline screens render, or set the font family explicitly on those screens, so no serif fallback appears. Unpaired screen: a primary action "Come associare il dispositivo" with three short steps. Offline screen: "Nuovo tentativo tra 5 s" with a countdown and "Riprova ora"; no spinner next to the button. Verify with `pnpm run verify -- --e2e`.

---

## 12. Phase 11 — Polish

Each item is small. Do them as separate commits in one pull request.

| ID | Change |
|---|---|
| P3-2 | Concentric radii: inner radius = outer radius − inset. With a 14 px pane and an 8 px inset the header radius is 6 px; or set the inset to 4 px and keep 10 px. |
| P3-5 | Any dialog not yet on `FrameDialog` fits its content. |
| P3-8 | Fix the stale "Catppuccin" comment in `ui/code/file_icon.dart`. |
| P3-11 | Replace fixed heights (title bar 42, tab bar 44, rows 28) with min-heights; check at text scale 1.4 and 2.0. |
| N14 | Tooltips only on truncated text (through `FrameMiddleEllipsis`). |
| N15 | Rounded hover shape on Settings nav items. |
| R8 | Extension status text: ellipsis + tooltip. |
| §8 | Raise the minimum window size to 680×560, or merge the session header into the title bar below 560 px height. |
| §6.13 | The palette no longer lists "Interrompi agente (Esc)" with a wrong key hint. |
| Theme editor | Replace the bright 2 px separator with the token border. |

---

## 13. Phase 12 — Final verification and documentation

1. **Full capture pass.** Repeat the audit's capture set (`01`–`46`, the `r2` hover/focus set, the `r5` and `v-*` states) at 1280×720, 1584×991 and 1920×1080, in dark and light. Store them in `docs/ui-exploration/captures-impl/final/`.
2. **Checklist** — every item must hold:
   - No overflow stripe or exception in any harness log.
   - No text below 11 px; the ratchet test is at its target baselines.
   - Every interactive control is reachable by Tab, shows a focus ring, and has a semantic label.
   - Escape closes the topmost layer everywhere.
   - Warning and danger colours appear only on real warnings and errors.
   - Every async action ends in a visible success, recoverable error or blocking error.
   - Every empty state has one action.
   - No English fragments or internal IDs in the Italian UI.
   - Every transition uses a `FrameMotion` token and has a reduced-motion variant.
   - Text scale 1.4 shows no clipping in the workspace, Settings and dialogs.
3. **Documentation.**
   - `DESIGN.md` §07: record the final spacing, type, size and motion tokens and the list of shared widgets.
   - `docs/theming.md`: new tokens (`inputBorder`, type roles).
   - `docs/install.md`: new features (in-pane diff, commit form, shortcuts, resume welcome, settings navigation, startup-animation toggle).
   - `docs/troubleshooting.md`: the overflow fixes and the error-message mapping (where to find "Dettagli").
   - `docs/ui-exploration/NAVIGATION-MAP.md`: layout persistence, Settings navigation, in-pane diff, the Escape rule.
   - Append a "Round 7: implementation status" section to `UI_UX_REVIEW.md` with one row per audit ID: done, changed, or deferred with the reason.
4. **Release check.** `pnpm run verify -- --release` and `pnpm run verify -- --e2e`, then `pnpm run pr`.

---

## 14. Traceability: audit ID → task

| Audit ID | Task | Audit ID | Task |
|---|---|---|---|
| P1-1, P1-2, N6 | 3.1 | P2-1, N3, N10 | 1.8, 1.1 |
| P1-3 | 3.2 | P2-2, N7 | 1.7 |
| P1-4 | 1.2, 10.2 | P2-3 | 6.3 |
| P1-5 | 10.1 | P2-4 | 6.6 |
| P1-6 | 4.3 | P2-5, N4 | 6.5 |
| P1-7 | 4.1 | P2-6 | 8.1–8.3 |
| P1-8 | 9.1 | P2-7 | 2.1, 2.5 |
| P1-10, N8 | 2.2, 6.1 | P2-8 | 2.1 |
| P1-11 | 1.5 | P2-9 | 2.6 |
| P1-12 | 1.6 | P2-10 | 3.3, 4.6, 5.6 |
| P1-13 | 2.1, 2.5 | P2-11 | 5.4, 4.5 |
| P1-14 | 2.3, 2.4 | P2-12 | 5.2 |
| P1-15, N11–N13 | 5.1 | P2-13 | 5.3 |
| P1-16 | 7.3, 3.2, 10.1 | P2-14 | 3.5 |
| P1-17 / N1 | 6.2 | P2-15 | 3.4 |
| P1-18 / N2 | 1.1 | P2-16 | 4.5 |
| R1, R2 | 1.2 | P2-17 | 10.3 |
| R3 | 1.4 | P2-18 | 10.4 |
| R4, R5, R6 | 4.7 | P2-19 | Deferred (D-1) |
| R7 | 5.6 | P2-20 | 7.8 |
| R8 | 4.5, Phase 11 | P2-21 | 7.2, 7.7 |
| R9 | 8.3 | P2-22 | 5.5 |
| N5 | 1.3 | P2-23 | 6.4 |
| N9 | 1.9 | P3-1 … P3-11 | 2.4, 3.6, 9.3, Phase 11 |
