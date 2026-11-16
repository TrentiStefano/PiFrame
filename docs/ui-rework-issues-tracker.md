# PiFrame UI Rework Issues Tracker

This document tracks all 21 reported UI issues, organized into 6 logical groups by UI section and similarity.

## Progress Overview
- [x] Group 1: Chat Pane — Message List, Compaction & Subagents (4/4 completed)
- [x] Group 2: Chat Pane — Title Bar & Header (1/1 completed)
- [x] Group 3: Chat Pane — Input Box & Composer (5/5 completed)
- [x] Group 4: Left Sidebar & Navigation (Sessions, Repo Pane, New Session Dialog) (5/5 completed)
- [x] Group 5: Right Sidebar (Agents & Git Changes) (3/3 completed)
- [x] Group 6: Settings Screen (3/3 completed)

---

## Group 1: Chat Pane — Message List, Compaction & Subagents
- [x] **1.1 Step grouping / compaction with thinking broken**: Fixed `StepGroupingMode.withThinking` in `transcript_grouping.dart` to recognize intermediate assistant reasoning text between tools in addition to explicit `<thinking>` blocks, preventing tool turns from dropping loose in the chat. Added settings toggle `showIntermediateAnswers` in `StepGroupingSettings` and settings UI (`Screenshot 2026-11-16 075716.png`).
- [x] **1.2 In-between agent answers placed between compacted step groups**: Partitioned intermediate assistant text turns into `IntermediateTextBlock` outside the compacted `StepsGroupBlock`s when `showIntermediateAnswers` is enabled (`showIntermediateAnswers: true`), following the visual sequence: user input -> compacted steps group -> intermediate reasoning answer -> compacted steps group -> final answer.
- [x] **1.3 Final answer card border vs in-between answer**: Updated `AssistantTurnFrame` with `isCard: bool`. When `isCard: true` (used for `FinalTextBlock` and `LiveTailBlock`), the assistant message is enclosed in a card with a subtle border and surface fill (`Screenshot 2026-11-16 080453.png`). When `isCard: false` (used for `IntermediateTextBlock`), it renders cleanly without a card border.
- [x] **1.4 Subagent notifications taking over chat**: Converted subagent task notification entries into `SubagentNotificationStep`s that compact into the intermediate steps group with a compact 1-line summary and smart-toy icon. In addition, subagents remain structured and accessible in the dedicated resizable Agents right sidebar tab (`Screenshot 2026-11-16 080637.png`).

---

## Group 2: Chat Pane — Title Bar & Header
- [x] **2.1 Chat title bar reorganization**:
  - Session title made larger (18/22px).
  - Folder icon restored next to session path; path placed on its own line below the top row of cards spanning the full width with middle ellipsis.
  - Context and Cost cards positioned to the left of the Session Status badge (which is positioned on the far right).
  - Plugin chips replaced with a single plugin icon chip displaying plugin count; clicking it opens a menu popup displaying all active plugin status cards (`Screenshot 2026-11-16 082758.png`).

---

## Group 3: Chat Pane — Input Box & Composer
- [x] **3.1 Remove duplicate stop button**: Only one stop button is presented; minimized bar has interrupt button and expanded input box has single stop button next to steer/followup.
- [x] **3.2 Light theme input box contrast**: Added border and subtle elevation box shadow in light mode so the container clearly stands out from the background (`Screenshot 2026-11-16 075020.png`).
- [x] **3.3 Restore ring glow animation**: Restored `ShimmerBorder` wrapped with `_ComposerSizeAnimator` and pointer hover glow via `_GlowPointerPainter`.
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

---

## Group 6: Settings Screen
- [x] **6.1 Settings section order**: Move the "Pi" section above the "General" section in the settings navigation sidebar.
- [x] **6.2 Pi CLI settings layout**: Realign the Output box to start at the same height as the "Quick commands" card, and give Output more horizontal space (`Screenshot 2026-11-16 085414.png`).
- [x] **6.3 Packages settings layout**: Expand and format the Installed Packages list to not be crammed and squished in the center (`Screenshot 2026-11-16 085711.png`).
