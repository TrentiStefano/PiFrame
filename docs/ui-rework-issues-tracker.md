# PiFrame UI Rework Issues Tracker

This document tracks all 30 reported UI issues across both rounds, organized into 9 logical groups by UI section and similarity.

## Progress Overview
- [x] Group 1: Chat Pane — Message List, Compaction & Subagents (5/5 completed)
- [x] Group 2: Chat Pane — Title Bar & Header (1/1 completed)
- [x] Group 3: Chat Pane — Input Box & Composer (5/5 completed)
- [x] Group 4: Left Sidebar & Navigation (Sessions, Repo Pane, New Session Dialog) (5/5 completed)
- [x] Group 5: Right Sidebar (Agents & Git Changes) (4/4 completed)
- [x] Group 6: Settings Screen (3/3 completed)
- [x] Group 7: Tasks/Todo Popup & Pane Animations (3/3 completed)
- [x] Group 8: Message List, Grouped Steps & Styling (3/3 completed)
- [x] Group 9: Settings View Polish & Performance (3/3 completed)
- [x] Group 10: Side Conversations & Companion Sidecar (1/1 completed)
- [x] Group 11: Git Branch Readability & Branch Picker Layout (2/2 completed)
- [x] Group 12: Transcript History Windowing & Card Border Precision (2/2 completed)
- [x] Group 13: Overlay Precision & Design Token Alignment (4/4 completed)

---

## Group 1: Chat Pane — Message List, Compaction & Subagents
- [x] **1.1 Step grouping / compaction with thinking broken**: Fixed `StepGroupingMode.withThinking` in `transcript_grouping.dart` to recognize intermediate assistant reasoning text between tools in addition to explicit `<thinking>` blocks, preventing tool turns from dropping loose in the chat. Added settings toggle `showIntermediateAnswers` in `StepGroupingSettings` and settings UI (`Screenshot 2026-11-16 075716.png`).
- [x] **1.2 In-between agent answers placed between compacted step groups**: Partitioned intermediate assistant text turns into `IntermediateTextBlock` outside the compacted `StepsGroupBlock`s when `showIntermediateAnswers` is enabled (`showIntermediateAnswers: true`), following the visual sequence: user input -> compacted steps group -> intermediate reasoning answer -> compacted steps group -> final answer.
- [x] **1.3 Final answer card border vs in-between answer**: Updated `AssistantTurnFrame` with `isCard: bool`. When `isCard: true` (used for `FinalTextBlock` and `LiveTailBlock`), the assistant message is enclosed in a card with a subtle border and surface fill (`Screenshot 2026-11-16 080453.png`). When `isCard: false` (used for `IntermediateTextBlock`), it renders cleanly without a card border.
- [x] **1.4 Subagent notifications taking over chat**: Converted subagent task notification entries into `SubagentNotificationStep`s that compact into the intermediate steps group with a compact 1-line summary and smart-toy icon. In addition, subagents remain structured and accessible in the dedicated resizable Agents right sidebar tab (`Screenshot 2026-11-16 080637.png`).
- [x] **1.5 "Full" step grouping option, text shimmer & smooth step transitions**: Added `StepGroupingMode.full` option ("Completo (Full)") that groups all intermediate tool calls, reasoning/thinking, and non-final assistant text into a single compacted step group. While the agent is working, replaced the spinning indicator with an animated loading-ui style text shimmer (`FrameTextShimmer`). Enhanced step transitions with a step-specific keying strategy and smooth easeInOut fade (180ms fade-out, 240ms fade-in) guaranteeing at least 100ms+ perceptible transition between consecutive agent commands. When settled, displays a super-compact view showing only the user prompt, expandable step summary indicator with step count and duration, and the agent's final answer.

---

## Group 2: Chat Pane — Title Bar & Header
- [x] **2.1 Chat title bar reorganization**:
  - Session title made larger (18/22px).
  - Folder icon restored next to session path; path placed on its own line below the top row of cards spanning the full width with middle ellipsis.
  - Context and Cost cards positioned to the left of the Session Status badge (which is positioned on the far right).
  - Plugin chips replaced with a single plugin icon chip displaying plugin count; clicking it opens a menu popup displaying all active plugin status cards (`Screenshot 2026-11-16 082758.png`).

---

## Group 3: Chat Pane — Input Box & Composer
- [x] **3.1 Remove duplicate stop button**: Only one stop button is presented: the minimized composer bar displays the inline Stop/Interrupt action button (`Screenshot 2026-11-17 080553.png`), while the expanded composer only shows the stop button in the bottom action bar next to steer (`Screenshot 2026-11-17 080522.png`), completely removing the redundant top status line stop button.
- [x] **3.2 Light theme input box contrast**: Added border and subtle elevation box shadow in light mode so the container clearly stands out from the background (`Screenshot 2026-11-16 075020.png`).
- [x] **3.3 Restore ring glow animation**: Fixed `ShimmerBorder` by painting the base border, highlight halo, and crisp light beam on `foregroundPainter` (on top of the container) and rendering a soft atmospheric glow halo on `painter` without bounding box clipping (`saveLayer(rect)` removed). Ensured full visibility in both light and dark modes, minimized and expanded states, and compliant with design literal ratchets.
- [x] **3.4 Minimized input box while responding**: Reverted input box to minimize into compact `_buildMinimizedBar` while agent is answering, displaying `_MinimizedElapsedTimer` in the minimized bar.
- [x] **3.5 Review changes button visibility**: Wrapped `ComposerReviewButton` in `if (hasModifiedFiles || isReviewing)` so it is completely hidden when there are no changes to review (`Screenshot 2026-11-16 084035.png`).

---

## Group 4: Left Sidebar & Navigation (Sessions, Repo Pane, New Session Dialog)
- [x] **4.1 Sessions repo collapse persistence**: Navigating away from and back to sessions (e.g. from settings) must retain the user's manual expand/collapse state for repository groups.
- [x] **4.2 Sessions "last active time" reset & layout**: Fix any reset of "last active time" upon startup. Move the last active time label below the session name with smaller text to prevent truncating session names (`Screenshot 2026-11-16 081349.png`).
- [x] **4.3 New session popup folder path & icon**: Fix path formatting and move the open folder icon outside of the text box (`Screenshot 2026-11-16 081731.png`).
- [x] **4.4 Repository pane minimum resize width & long path readability**: Reduce minimum resize width by ~50% and fix long path display at the top of the repo pane (`Screenshot 2026-11-16 082038.png`).
- [x] **4.5 Repository pane three-dots button bug**: Fix the three-dots button opening a text input box with the letter 'c' instead of the intended menu (`Screenshot 2026-11-16 082602.png`).

---

## Group 5: Right Sidebar (Agents & Git Changes)
- [x] **5.1 Agents tab resizability & completed subagents section**: Make the Agents tab resizable (width adjustable between 240px and 700px with a divider drag handle); group completed subagents under a collapsible/normally minimized section.
- [x] **5.2 Git changes tab minimum resize dimension**: Allow Git changes pane to resize smaller (half of previous min dimension down to 160px via `kCompanionMinWidth`).
- [x] **5.3 Git action buttons layout**: Change fetch, push, pull, sync buttons to icon-only with tooltips, positioned to the left of the commit button in a unified action row.
- [x] **5.4 Git changes pane segmented switcher and browser button deduplication**: Removed the redundant browser `IconButton` on the right side of the pane header, and aligned the Git Changes header with the Web Browser header (`Screenshot 2026-11-17 122247.png`) using the unified segmented control pill switcher with `Git Changes` card selected and `Web Browser` unselected (`Screenshot 2026-11-16 145941.png`).

---

## Group 6: Settings Screen
- [x] **6.1 Settings section order**: Move the "Pi" section above the "General" section in the settings navigation sidebar.
- [x] **6.2 Pi CLI settings layout**: Realign the Output box to start at the same height as the "Quick commands" card, and give Output more horizontal space (`Screenshot 2026-11-16 085414.png`).
- [x] **6.3 Packages settings layout**: Expand and format the Installed Packages list to not be crammed and squished in the center (`Screenshot 2026-11-16 085711.png`).

---

## Group 7: Tasks/Todo Popup & Pane Animations
- [x] **7.1 Tasks popup expansion**: When new todo tasks are added, only show the newly added ones instead of expanding the entire full list of all previous tasks (`Screenshot 2026-11-16 092118.png`). Includes a filter banner with "Mostra tutti (N)" action.
- [x] **7.2 Tasks popup "+" button placement**: Move the "+" button to add a task away from the middle of the header row into a proper location on the far right aligned with the action controls (`Screenshot 2026-11-16 092118.png`).
- [x] **7.3 Smooth pane expand/minimize animation**: When minimizing or expanding main panes, other panes temporarily disappear for a second. Fixed `_entryAlpha` and `FrameEnter` in `app_shell.dart` so open panes keep opacity at 1.0 during transitions.

---

## Group 8: Message List, Grouped Steps & Styling
- [x] **8.1 Step group independent expansion**: Expanding one step group currently expands all step groups above and below. Added `groupId` support in `step_group_expansion.dart` and `steps_group.dart` so each step block has an independent expansion key.
- [x] **8.2 Grouped steps yellow warning icon bug**: Fix spurious yellow warning icon on `Completed X steps` header when all steps within the group completed successfully (`Screenshot 2026-11-16 144441.png`). Isolated group-level tool errors from whole-turn stopReason errors.
- [x] **8.3 Alignment & Typography**: Indented grouped steps by 20px to the right, pushed final agent answer card to the left (`Alignment.topLeft`, `maxWidth: 820`), and gave intermediate reasoning answers a slightly darker/more muted text color (`tokens.textSecondary`) than final answers (`Screenshot 2026-11-16 144441.png`).

---

## Group 9: Settings View Polish & Performance
- [x] **9.1 Settings title bar "Completed" text**: Removed the active session status badge ("Completed") that spuriously appeared in the title bar of the PiFrame Settings view (`Screenshot 2026-11-16 150305.png`).
- [x] **9.2 Agents settings space utilization**: Expanded the Agents settings page layout to use `_wideContentMaxWidth` (1360px) rather than being constrained to a narrow 760px column (`Screenshot 2026-11-16 150305.png`).
- [x] **9.3 Packages settings loading & layout**: Preserved package list state during background update checks, prevented RenderFlex overflow on narrow viewports, and ensured clear package card layout.

---

## Group 10: Side Conversations & Companion Sidecar (`/side` and `/btw`)
- [x] **10.1 Side conversations companion pane & session history**:
  - Restored `/side` and `/btw` command triggers from the composer.
  - Replaced the inner `SideSplit` transcript wrapper with integration directly into the full-height Chat Sidecar (`AgentSidecarLayout` / `AgentActivitySidecar`).
  - Added multi-conversation history support (`SideConversationRecord`) per session: users can ask side questions, view a horizontal pill list of all past and active side conversations with status indicators, switch between them with conversation transcripts preserved, delete old side conversations, and start new ones with a dedicated `+` button.
  - Added dual tabs `[ Agenti (N) ]` and `[ Laterale (M) ]` in the sidecar header when both agents and side threads are active, sharing the draggable resize handle and collapsed sidecar strip.
  - Updated documentation in [install.md](file:///c:/Personale/Repos/PiFrame/PiFrame/docs/install.md) and [troubleshooting.md](file:///c:/Personale/Repos/PiFrame/PiFrame/docs/troubleshooting.md).

---

## Group 11: Git Branch Readability & Branch Picker Layout
- [x] **11.1 Branch name readability in Branch Picker and Git Changes Pane**:
  - Enlarged `BranchPickerDialog` max width from 540px to 740px (with responsive constraint up to 94% on smaller screens) and max height up to 600px.
  - Redesigned branch picker items with a two-level hierarchy: line 1 displays check/fork icon, full branch name with expanded flex width, ahead/behind indicators, and current branch badge; line 2 displays the upstream remote (`origin/...`) clearly beneath the branch name. Added hover tooltips with full branch and upstream details (`branch_1.png`).
  - Improved Git Changes header branch chip with adaptive `LayoutBuilder`: removed hardcoded `maxWidth: 160`, allowing the chip to expand up to 65% of available pane width (up to 450px) on standard viewports, and cleanly wrapping to a dedicated row on narrow companion panes (<360px). Added branch name to the chip tooltip (`branch_2.png`).
- [x] **11.2 Branch Picker search bar layout & ESC button integration**:
  - Replaced the fragmented layout where the focus ring was drawn only around the raw text field leaving the search icon and ESC button awkwardly disconnected (`Screenshot 2026-11-17 103150.png`).
  - Integrated the search bar into a unified input container (`tokens.surfaceElevated`, `tokens.radiusMd`) with reactive `focusRing` highlighting on focus.
  - Aligned the search icon inside on the left and transformed the `ESC` chip into an interactive, properly padded keycap button on the right with click-to-dismiss behavior (`ValueKey('branch-picker-esc-btn')`).

---

## Group 12: Transcript History Windowing & Card Border Precision
- [x] **12.1 Answer-based transcript history windowing (10 agent answers kept loaded)**:
  - Transitioned the transcript windowing logic in `transcript_view.dart` from a raw entry counter (which previously counted tool calls, tool results, and internal steps against the window, causing prompts to be prematurely hidden) to counting the last 10 assistant answers (`_initialVisibleAnswers = 10`).
  - Intermediate grouped steps (tool calls, tool results, thinking) no longer count against the window quota.
  - Guaranteed that the user prompt initiating any loaded turn is never unloaded or hidden.
  - Updated "Carica messaggi precedenti" / "Load earlier messages" pagination to step backward by 10 agent answers (`_answersPageSize = 10`) per click.
  - Replaced fragile `GlobalKey` anchor tracking in `SmartTranscriptChildDelegate` with stable `ValueKey`s and smooth offset jumping (`jumpTo(oldOffset + addedHeight)`).
  - Verified with comprehensive widget tests in `apps/pi_frame/test/transcript_history_window_test.dart`.
- [x] **12.2 Accurate assistant card border lifecycle (final answer only)**:
  - Fixed premature card border display in `transcript_grouping.dart` where an in-progress intermediate assistant message was designated as `finalAssistantEntry` between tool steps while `live.isRunning` was true.
  - Emits in-progress assistant entries as `IntermediateTextBlock` (`isCard: false`, no card border) while `turn.isLastTurn && live.isRunning`.
  - Updated `LiveTailBlock` in `transcript_view.dart` to use `isCard: false`.
  - Only settled turns with completed execution receive `FinalTextBlock` (`isCard: true`, rendered with card border).

---

## Group 13: Overlay Precision & Design Token Alignment
- [x] **13.1 Settings switch list tile shape and padding**:
  - Replaced unpadded, sharp rectangular ink highlight (`BorderRadius.zero`) in `SwitchListTile` / `ListTile` across settings sections (`aspetto_section.dart`, `daemon_section.dart`, `updates_section.dart`) with `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.radiusSm))` and `contentPadding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2)`.
  - Added global `listTileTheme` with `tokens.radiusSm` to `ThemeSpec` (`theme_spec.dart`), ensuring hover and focus overlays match component card borders and maintain comfortable internal margins (`Screenshot 2026-11-17 141739.png`).
- [x] **13.2 Tooltip theme elevation, borders and contrast**:
  - Replaced harsh white background / black text tooltips in dark mode (`Screenshot 2026-11-17 141704.png`, `Screenshot 2026-11-17 141640.png`) with design token integrated `TooltipThemeData` in `ThemeSpec` (`theme_spec.dart`).
  - Tooltips now use `tokens.surfaceElevated` background, `tokens.displayText` foreground, `Border.all(color: tokens.borderStrong, width: 0.8)`, `tokens.radiusSm`, `waitDuration: 300ms`, and delicate drop shadows.
- [x] **13.3 Minimized composer pointer glow overlay alignment**:
  - Fixed painter bounding box distortion in `composer.dart` where `_GlowPointerPainter` previously painted onto an inner child (~24px tall) inside outer padding, causing it to collapse into a detached stadium/capsule shape (`Screenshot 2026-11-17 141950.png`).
  - Lifted the glow pointer painter and mouse region to wrap the outer composer `Container` directly, ensuring the glow effect follows the exact outer container geometry and corner radius (`_composerRadius(tokens)`). Inner tap interactions and padding now neatly live within the child `InkWell`.


