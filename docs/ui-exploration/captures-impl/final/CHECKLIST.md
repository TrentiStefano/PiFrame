# Final verification checklist (plan §13.2)

Branch: ui/phase-11-12-integration. Captures in this folder were taken from the harness run `final`
at 1280x720, 1584x991 and 1920x1080 (dark and light, theme switched with the title-bar toggle; each
dark/light pair was compared byte-wise and differs), plus compact 800x900 (dark), text scale 1.4 and
reduced motion (dark, 1584x991).

Gate results at this HEAD: `flutter analyze` prints "No issues found!" for apps/pi_frame and
packages/pi_frame_theme; full `flutter test` passes (1057 tests).

Honesty note: where an item was not exercised in this pass, it is marked FAIL with what is missing,
not PASS.

| # | Item | Result | Evidence / what is missing |
|---|------|--------|----------------------------|
| 1 | No overflow stripe or exception in any harness log | PASS | `pnpm harness logs --run final --lines 8000`: 0 lines matching "overflow" or "exception" (184 lines in the window). Caveat: the log window is the last run only. Visible clipping at text scale 1.4 is tracked under item 10. |
| 2 | No text below 11 px; ratchet at target baselines | FAIL | `apps/pi_frame/test/design_literals_lint_test.dart` passes, but baseline `fontSize below 11` is still 2 (target 0). Duration baseline was set to the measured 10 during the merge. No literal was migrated in this phase, so no baseline could be lowered. |
| 3 | Every interactive control reachable by Tab, focus ring, semantic label | FAIL | Not verified. No keyboard traversal or focus-ring capture was made in this pass. |
| 4 | Escape closes the topmost layer everywhere | FAIL | Partial. Escape closed the command palette and the new-session dialog in the flow (captures command-palette-*, dialog-new-session-*). Not checked for nested layers (side conversation, theme editor, settings sub-dialogs). |
| 5 | Warning and danger colours only on real warnings and errors | FAIL | Not audited. Captures show the danger colour on the "Interrompi" stop control during a run (workspace-running-*) and a warning-tinted "Salvataggio disabilitato: In esecuzione" banner (editor while running). No review of every use was done. |
| 6 | Every async action ends in a visible success, recoverable error or blocking error | FAIL | Not verified end to end in this pass. Only the send/run path was exercised (workspace-running-*, side-split-*). |
| 7 | Every empty state has one action | FAIL | Not verified. No empty-state capture was taken. |
| 8 | No English fragments or internal IDs in the Italian UI | FAIL | settings-pi-cli-1280x720-*, settings-pi-cli-1584x991-*, settings-pi-cli-1920x1080-*: the output panel heading reads "Output". Git pane (git-list-*, workspace-running-*): "Fetch", "Pull", "Push", "Sync", "Commit", and a "Browser" chip. Side conversation (side-split-*): "Hello from fake-pi!" is fixture text from the fake Pi. |
| 9 | Every transition uses a FrameMotion token and has a reduced-motion variant | FAIL | Not proven. reduced-motion-frame1-1584x991-dark.png and reduced-motion-frame2-1584x991-dark.png (about 1 s apart, reduced motion on, during a run) differ, but the difference is streamed token text, so it does not show motion stopped. Reduced-motion widget tests exist (settings_packages_reduced_motion_test.dart) but do not cover every transition. |
| 10 | Text scale 1.4 shows no clipping in workspace, Settings and dialogs | FAIL | text-scale-1.4-workspace-1584x991-dark.png: in the Git pane header the "Browser" chip is clipped and overlaps the globe icon next to it. Settings (text-scale-1.4-settings-aspetto-1584x991-dark.png) shows no clipping. Dialog (text-scale-1.4-dialog-1584x991-dark.png) was captured but not reviewed in this pass. |

## Summary

- PASS: 1 (item 1).
- FAIL: 9. Items 2, 8 and 10 have concrete visible or measured failures. Items 3 to 7 and 9 were not verified in this pass.
