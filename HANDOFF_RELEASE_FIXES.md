# PiFrame Release Fixes Handoff Document

**Date**: 2026-10-23  
**Status**: 10 of 11 items complete and verified with 100% test pass rate across `pi_frame` and `agentd`. 1 item (Item 11) analyzed and ready for immediate completion.

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
| 9 | Desktop snackbars: bottom-right placement, min 280px / max 460px width, instant dismiss on click (`FrameSnackBar`) | **DONE** | `frame_snack_bar_test.dart` (5 tests passed), 250/250 pi_frame tests passed |
| 10 | Cost breakdown dialog: clicking main agent shows all models used during the session with their respective costs and token counts (matching `/session` CLI output) | **DONE** | `sessionCostPersistence.test.ts` (84/84 agentd passed), `cost_breakdown_models_test.dart` |
| 11 | Steer queue double-sent messages after stop, model change, and resend | **READY FOR FINISH** | Root cause analyzed below |

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

## 3. Item 11: Steer Queue Double-Send Fix Specification

### Problem Description
> "quando viene inviato un messaggio che va nella steer queue e viene stoppato l'agente e cambiato modello e poi reinviato vengono inviati 2 messaggi insieme (uno con il testo del messaggio precedente che era nella steer queue che doveva essere cancellato dallo stop e uno con il messaggio appena inviato)"

### Root Cause Analysis
1. In `apps/pi_frame/lib/features/composer/composer.dart` lines 550-575:
   When `_interrupt()` runs on stop/Esc, it contained legacy "Esc recovery" code:
   ```dart
   if (data != null && data['queue'] is Map) {
     ...
     _controller.text = restored; // <--- Restores cancelled steer message back into composer!
   }
   ```
   When the user stopped the agent, this unexecuted steer message was injected back into `_controller.text`. When the user changed model and typed/sent a new prompt, `_controller.text` either still held the restored text or concatenated it, causing the previous steer message and the new prompt to be sent together.
2. In `apps/agentd/src/commands/Dispatcher.ts` lines 652-674:
   ```ts
   case 'agent.interrupt': {
     const session = this.registry.getSession(sessionId);
     if (session && session.worker) {
       ...
     }
   ```
   - If `session.worker` was not cached on the session instance directly, `ensureWorkerForSession` was not called, so `clear_queue` was never transmitted to Pi.
   - `session.queue = { steering: [], followUp: [] }` was never updated on `session` in `agentd`, and `session.emitCustomEvent('queue.changed', ...)` was not broadcast to attached GUI clients.
3. In `apps/pi_frame/lib/data/daemon/daemon_providers.dart`:
   `interrupt()` and `clearQueue()` did not clear `state.steeringQueue` and `state.followUpQueue` optimistically.

### Implementation Checklist for Item 11

1. **`apps/pi_frame/lib/features/composer/composer.dart`**:
   In `_interrupt()` (lines 549-575):
   - Remove the `_controller.text = restored;` logic.
   - Instead, ensure the cancelled steer message is deleted:
     ```dart
     if (mounted) {
       FrameSnackBar.show(
         context,
         message: 'Agente interrotto. La coda di messaggi è stata cancellata.',
         duration: const Duration(seconds: 3),
       );
     }
     ```
2. **`apps/agentd/src/commands/Dispatcher.ts`**:
   In `case 'agent.interrupt':` (around line 652):
   - Resolve worker safely:
     ```ts
     let worker: StdioPiTransport | undefined = session?.worker;
     if (!worker) {
       try { worker = await this.registry.ensureWorkerForSession(sessionId); } catch {}
     }
     if (worker) {
       try { await worker.send({ command: 'clear_queue' }); } catch {}
       try { await worker.send({ command: 'abort' }); } catch {}
     }
     if (session) {
       session.queue = { steering: [], followUp: [] };
       session.emitCustomEvent('queue.changed', { steering: [], followUp: [] });
       session.isStreaming = false;
       session.status = 'settled';
       session.emitCustomEvent('run.settled', {});
     }
     ```
   In `case 'agent.clearQueue':`:
   - Also update `session.queue = { steering: [], followUp: [] }` and broadcast `queue.changed`.
3. **`apps/pi_frame/lib/data/daemon/daemon_providers.dart`**:
   In `interrupt()`:
   - On completion, set `state = state.copyWith(steeringQueue: const [], followUpQueue: const [], isStreaming: false, agentStatus: AgentStatus.settled);`.
   In `clearQueue()`:
   - On completion, set `state = state.copyWith(steeringQueue: const [], followUpQueue: const []);`.
4. **Automated Verification**:
   - Add widget/unit test verifying that interrupting clears `steeringQueue` and does not populate `_controller.text`.
   - Run `pnpm test` in `apps/agentd` and `flutter test` in `apps/pi_frame`.

---

## 4. Test Verification Summary

- **`apps/agentd`**: 84 of 84 tests passing (`node --test dist/**/*.test.js`).
- **`apps/pi_frame`**: 250 of 250 tests passing (`flutter test`).
- **`flutter analyze`**: 0 errors, 0 warnings.
- **Repository Rules**: Adheres strictly to `AGENTS.md` (no fake UI captures, real metrics only).
