# Final verification checklist (plan §13.2)

Branch: ui/phase-11-12-integration (HEAD afca965 before the final cleanup commit 352a245).

Gates at this HEAD: `flutter analyze` prints "No issues found!" for apps/pi_frame and
packages/pi_frame_theme. Full `flutter test` passes: 1069 passed, 3 skipped.

Captures in this folder come from the harness run `final` (1584x991, dark unless the name says light).
Text scale 1.4 captures: `textscale14-*.png`. Keyboard focus capture: `a11y-divider-focus-dark.png`.

Result legend: PASS, PASS-with-notes (passes what was checked; the notes are open limits), FAIL.

| # | Item | Result | Evidence |
|---|------|--------|----------|
| 1 | No overflow stripe or exception in any harness log | PASS | `pnpm harness logs --run final --lines 8000` after the text-scale 1.4 captures (workspace, Aspetto, Pi CLI, new-session dialog, command palette): 0 lines matching "RenderFlex overflowed" or "exception". Only the final run's log window was checked. |
| 2 | No text below 11 px; ratchet at target baselines | PASS-with-notes | `apps/pi_frame/test/design_literals_lint_test.dart`: `fontSize below 11` baseline is 0 (was 2). Commit 1202e9d moved the last sub-11 px literals to FrameText roles. Notes: other ratchet baselines are not at target: `fontSize numeric literal` 26, `BorderRadius.circular numeric` 4, `Duration(milliseconds:) numeric` 10, `Curves.` 2, `BoxShadow(` 10, `GestureDetector(` 4. |
| 3 | Every interactive control reachable by Tab, focus ring, semantic label | PASS-with-notes | `apps/pi_frame/test/a11y_tab_sweep_test.dart` (passes; checks every Tab stop has a label and a focus indicator). Captures: `a11y-tab-01-first-stop-dark.png`, `a11y-tab-03-dark.png`, `a11y-tab-05-sessions-row-dark.png`, `a11y-tab-06-banner-action-dark.png`, `a11y-tab-18-dark.png`, `a11y-tab-26-dark.png`. Divider focus: `a11y-divider-focus-dark.png`. Cleanup commit 352a245 wraps FrameIconAction and FrameListRow in FrameFocusRing. Note: the sweep accepts a Material ink response as the indicator for some stops (for example the composer chips), so those stops show no FrameFocusRing. |
| 4 | Escape closes the topmost layer everywhere | PASS | `apps/pi_frame/test/escape_everywhere_test.dart` and `escape_layers_test.dart` pass in the full suite. Capture flow: Escape closed the new-session dialog (`textscale14-dialog-new-session.png` was taken before the Escape) and the command palette was opened from the title bar. |
| 5 | Warning and danger colours only on real warnings and errors | PASS-with-notes | v2 audit, commit 7a7c570 (warning and danger reserved for real warnings and errors). Danger colour on destructive actions is by design per plan task 1.1. |
| 6 | Every async action ends in a visible success, recoverable error or blocking error | FAIL | Commit 0258ee2 makes git fetch, pull, push and sync confirm success. Gap: session create with no id is silent (no success, no error shown). |
| 7 | Every empty state has one action | FAIL | Compliant, one action each: git clean state (Aggiorna, `git_changes_pane.dart`), session tree (`session_tree_dialog.dart`), MCP servers (Apri file di configurazione), agents (Apri Pacchetti), branch picker no-match state (commit 27ab7f4). Gap: the sessions sidebar empty state "Nessuna sessione trovata" has no action (seen in the sidebar with the daemon offline, `scratch` capture t10-start, not kept in this folder). Not decided: the first-run welcome view shows two actions (Nuova sessione, Esplora sessioni); it is not a list empty state. |
| 8 | No English fragments or internal IDs in the Italian UI | PASS | Fetch, Pull, Push, Sync, Commit, Browser and Output are accepted loanwords per task 1.7's rule. `apps/pi_frame/test/localization_copy_lint_test.dart` passes. Captures: `textscale14-settings-pi-cli.png` (Output heading), workspace capture `textscale14-workspace.png` (Git pane buttons). |
| 9 | Every transition uses a FrameMotion token and has a reduced-motion variant | FAIL | Reduced motion for the three pulse loops (startup assemble, sessions working dot, subagent orbit) is covered by `apps/pi_frame/test/motion_reduced_test.dart` (passes). Frames: `item9-reduced-motion-subagent-frame1.png` and `item9-reduced-motion-subagent-frame2.png` differ only in the elapsed timer (0:04 vs 0:05); the orbit is in the same position. `item9-reduced-motion-run-frame1.png` and `-frame2.png` differ by streamed text. `item9-control-motion-on-frame1.png` is the motion-on control. Not complete: the ratchet still counts 10 numeric `Duration(milliseconds:)` literals, so not every transition uses a token. Commit 352a245 corrects the `pulseLoop` doc and the working dot already uses `FrameMotion.pulseLoop`. |
| 10 | Text scale 1.4 shows no clipping in workspace, Settings and dialogs | PASS-with-notes | Run `final`, dark, text scale 1.4 at 1584x991. Captures: `textscale14-workspace.png` (Git pane with commit form open; the Browser chip is no longer clipped, fixed in d54e55d), `textscale14-settings-aspetto.png`, `textscale14-settings-pi-cli.png`, `textscale14-dialog-new-session.png`, `textscale14-command-palette.png`. No clipping seen in these five. Notes: light theme at 1.4 and the other settings sub-pages were not captured. |

## Summary

- PASS: 3 (items 1, 4, 8).
- PASS-with-notes: 4 (items 2, 3, 5, 10).
- FAIL: 3 (items 6, 7, 9). Each is listed with its gap above.
- Stale captures from the earlier pass (`text-scale-1.4-*`, `textscale14-workspace-agents-overlay.png`, `textscale14-workspace-rail-attempt.png`) were removed; the `textscale14-*` set above replaces them.
