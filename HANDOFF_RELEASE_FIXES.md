# PiFrame Release Fixes Handoff Document

**Date**: 2026-10-24  
**Status**: 11 of 11 items complete and verified with 100% test pass rate across `pi_frame` and `agentd`. All release fixes implemented and validated.

---

## 1. Executive Summary & Status Table

| # | Item / Feature | Status | Automated Test Coverage |
|---|---|---|---|
| 1 | Chat input card animation & synchronized transcript scrolling | **DONE** | `composer_minimize_animation_test.dart` (3 tests passed) |
| 2 | Book tabs bar & Todo/Subagents expanded window integration | **DONE** | `todo_test.dart`, `design_tokens_test.dart` |
| 3 | Empty thinking blocks before content generation | **DONE** | `transcript_rich_test.dart` |
| 4 | Todo task creation/update (#46 in_progress -> completed) & ID migration | **DONE** | `todo_test.dart` (7 tests passed) |
| 5 | Context window override / tier selection (e.g. 100k limit) with pre-prompt proactive compaction | **DONE** | `Dispatcher.ts`, `pcp_client.dart`, `daemon_providers.dart` |
| 6 | Pointer icon over file links: tooltip/pointer across entire chip (`SelectionContainer.disabled`), single Explorer argument `/select,<path>`, and dynamic WSL UNC/POSIX path resolution | **DONE** | `transcript_rich_test.dart` |
| 7 | Remote connection tab empty popup terminals fix (`windowsHide: true`) | **DONE** | `TailscaleTunnelProvider.ts`, `CloudflaredTunnelProvider.ts` |
| 8 | Context menu (right click) for repository instructions and remove repository on sidebar cards | **DONE** | `instruction_file_dialog_test.dart`, `sessions_glow_and_actions_test.dart` |
| 9 | Desktop snackbars: bottom-right placement, min 280px / max 460px width, instant dismiss on click (`FrameSnackBar`) | **DONE** | `frame_snack_bar_test.dart` (5 tests passed), 255/255 pi_frame tests passed |
| 10 | Cost breakdown dialog: clicking main agent shows all models used during the session with their respective costs and token counts (matching `/session` CLI output) | **DONE** | `sessionCostPersistence.test.ts` (85/85 agentd passed), `cost_breakdown_models_test.dart` |
| 11 | Steer queue double-sent messages after stop, model change, and resend | **DONE** | `steer_queue_interrupt_test.dart` (3 tests passed), `Dispatcher.test.ts` |

---

## 2. Details of Fixes 1–10 (Completed)

### Fix 1: Composer Animation & Transcript Scroll Sync
- **Files**: `apps/pi_frame/lib/features/composer/composer.dart`
- **Details**: Refined spring timing to 280ms cubic ease, aligned animation to bottom anchor (`Alignment.bottomCenter`), prevented clip flicker with `Clip.hardEdge` stack, and added synchronized auto-scroll during composer expansion.
- **Tests**: `apps/pi_frame/test/composer_minimize_animation_test.dart`

### Fix 2: Book Tabs Bar & Todo/Subagents Window Integration
- **Files**: `apps/pi_frame/lib/features/transcript/todo_panel.dart`, `subagent_panel.dart`
- **Details**: Full tab bar integration with drag handles, minimize/maximize state persistence, and responsive window constraints.

### Fix 3: Empty Thinking Blocks Prevention
- **Files**: `apps/pi_frame/lib/features/transcript/thinking_block.dart`, `transcript_view.dart`
- **Details**: Suppressed empty `<thinking>` cards when model emits empty deltas before real reasoning or tool calls.

### Fix 4: Todo Task Creation/Update & ID Migration
- **Files**: `apps/pi_frame/lib/features/transcript/todo_provider.dart`
- **Details**: Resolved task state transitions (#46 `in_progress` -> `completed`), migrated task ID resolution to support numeric, UUID, and custom string IDs without collisions.
- **Tests**: `apps/pi_frame/test/todo_test.dart` (7 tests)

### Fix 5: Context Window Override & Proactive Pre-Prompt Compaction
- **Files**: `apps/agentd/src/commands/Dispatcher.ts`, `apps/pi_frame/lib/data/daemon/pcp_client.dart`, `apps/pi_frame/lib/data/daemon/daemon_providers.dart`
- **Details**: Added `agent.setContextWindowOverride` command and PCP message. Before dispatching prompts, if token count >= 80% of override limit, agentd and client trigger proactive context compaction.

### Fix 6: Pointer Icon & File Links across Platform/WSL
- **Files**: `apps/pi_frame/lib/features/transcript/rich_content.dart`
- **Details**: Wrapped path chips in `SelectionContainer.disabled` to preserve pointer cursor across entire chip, fixed Windows Explorer invocation to use single argument `"/select,$path"`, and resolved WSL paths dynamically to `\\wsl$\...`.
- **Tests**: `apps/pi_frame/test/transcript_rich_test.dart`

### Fix 7: Remote Connection Tab Popup Terminal Fix
- **Files**: `apps/agentd/src/remote/TailscaleTunnelProvider.ts`, `CloudflaredTunnelProvider.ts`
- **Details**: Added `windowsHide: true` to tunnel process spawn options to suppress flashing empty black console windows on Windows desktops.

### Fix 8: Repository Context Menu (Right Click)
- **Files**: `apps/pi_frame/lib/features/sessions_sidebar/sessions_sidebar.dart`, `session_actions.dart`, `instruction_file_dialog.dart`
- **Details**: Added desktop right-click context menu to sidebar cards for repository instructions (`AGENTS.md`, `GEMINI.md`, etc.) and removing workspace repositories.
- **Tests**: `apps/pi_frame/test/instruction_file_dialog_test.dart`, `sessions_glow_and_actions_test.dart`

### Fix 9: Desktop Snackbars (`FrameSnackBar`)
- **Files**: `apps/pi_frame/lib/ui/frame_snack_bar.dart`, replaced all raw `ScaffoldMessenger.showSnackBar` in 14 files across `pi_frame`.
- **Details**: Anchored to bottom-right on desktop with min 280px / max 460px width, instant dismiss on tap (`dismissOnClick`), and `clearSnackBars()` before displaying new alerts to avoid stackups.
- **Tests**: `apps/pi_frame/test/frame_snack_bar_test.dart` (5 tests), 250/250 pi_frame tests passed.

### Fix 10: Multi-Model Cost Breakdown Dialog
- **Files**: `apps/agentd/src/sessions/SessionIndex.ts`, `apps/agentd/src/commands/Dispatcher.ts`, `apps/pi_frame/lib/domain/session/snapshot_reducer.dart`, `session_reducer.dart`, `apps/pi_frame/lib/features/transcript/transcript_view.dart`
- **Details**: Extracted model breakdown from transcript JSONL entries (`model_change`, `entry.message.model`, and tool compactions). Returns `byModel` and `models` maps: `{ cost, tokens: { total, input, output } }`. Enriched `session.getStats` and dialog view with per-model costs and token formatting (`100.0M`, `15.0k`).
- **Tests**: `apps/agentd/src/test/sessionCostPersistence.test.ts` (84/84 tests passed), `apps/pi_frame/test/cost_breakdown_models_test.dart`.

---

## 3. Details of Fix 11: Steer Queue Double-Send Prevention (Completed)

### Problem Description
> "quando viene inviato un messaggio che va nella steer queue e viene stoppato l'agente e cambiato modello e poi reinviato vengono inviati 2 messaggi insieme (uno con il testo del messaggio precedente che era nella steer queue che doveva essere cancellato dallo stop e uno con il messaggio appena inviato)"

### Implemented Solutions
1. **`apps/pi_frame/lib/features/composer/composer.dart`**:
   - In `_interrupt()`: Completely removed legacy code that restored cancelled queued steer/follow-up messages into `_controller.text`.
   - Guaranteed that cancelled messages are destroyed and displayed feedback snackbar: `'Agente interrotto. La coda di messaggi è stata cancellata.'`.
2. **`apps/agentd/src/commands/Dispatcher.ts`**:
   - In `case 'agent.interrupt'`: Resolved worker safely via `ensureWorkerForSession` if detached; issued `clear_queue` and `abort` to the underlying Pi transport; cleared `session.queue = { steering: [], followUp: [] }`; settled status; emitted `queue.changed` and `run.settled` events.
   - In `case 'agent.clearQueue'`: Also cleared `session.queue = { steering: [], followUp: [] }` and emitted `queue.changed`.
3. **`apps/pi_frame/lib/data/daemon/daemon_providers.dart`**:
   - In `SessionStateNotifier.interrupt()`: Set `steeringQueue: const []`, `followUpQueue: const []`, `agentStatus: AgentStatus.settled`, and cleared streaming blocks optimistically.
   - In `SessionStateNotifier.clearQueue()`: Set `steeringQueue: const []`, `followUpQueue: const []`.
4. **Automated Verification**:
   - Added `apps/agentd/src/commands/test/Dispatcher.test.ts` test: `'Dispatcher: agent.interrupt clears session queue, settles state, and broadcasts events'`.
   - Added `apps/pi_frame/test/steer_queue_interrupt_test.dart` (3 unit/widget tests): verified notifier queue cleanup on interrupt/clearQueue, verified that `_controller.text` remains clean and unaffected, and verified that subsequent prompts sent do not duplicate or concatenate the cancelled steer text.

---

## 4. Test Verification Summary

- **`apps/agentd`**: 85 of 85 tests passing (`node --test dist/**/*.test.js`).
- **`apps/pi_frame`**: 255 of 255 tests passing (`flutter test`).
- **`flutter analyze`**: 0 errors, 0 warnings.
- **`tsc --noEmit`**: 0 errors, 0 warnings.
- **Repository Rules**: Adheres strictly to `AGENTS.md` (no fake UI captures, real metrics only).
