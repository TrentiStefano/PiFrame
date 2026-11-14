# PiFrame UI navigation map

A working map of PiFrame's routes, shell states, panes, dialogs, responsive layout, and motion. It is intended as a handoff for an agent reviewing the UI as a whole. Screenshot links point to real Flutter renders in this folder.

## Capture scope and caveats

- Desktop captures use the isolated developer UI harness (`pnpm harness`); mobile web captures use the repository's remote pairing E2E setup with Playwright WebKit emulation. Both are real Flutter renders, not screen mockups or screen grabs of the user's desktop.
- Desktop harness runs used private `PI_FRAME_HOME` and fake-pi. Mobile web E2E runs used temporary `PI_FRAME_HOME`, `HOME`, `USERPROFILE`, `PI_CODING_AGENT_DIR`, and `PI_CODING_AGENT_SESSION_DIR`, plus fake-pi; final mobile screenshots contain only the generated `workspace` fixture, not the user's Pi sessions.
- Desktop screenshots use Italian UI text because the test home inherited the app's locale; mobile uses `it-IT`. Desktop viewport captures include 744×891, 1424×991, 1584×991, and 1784×1041. Mobile web screenshots are in `web/iphone-12/` and `web/iphone-18/`; see the device-specific profile and Safari limitations below.
- The early test session used the repository as its working directory. Git Changes therefore includes files in `docs/ui-exploration/` created during capture in screenshots 08 and 11–41; counts and file names in those screenshots are not baseline app data. Do not review that content as a designed fixture. Screenshots 42–46 use a separate, controlled Git repository under `~/.piframe-harness/ui-git-fixture/workspace` with staged/unstaged sample files; no repository source files were changed.
- The Packages settings tab remained on a loading indicator with fake-pi during capture. `13-settings-packages.png` records that observed state; the Packages steady state remains unverified and is not evidence that the production package list should remain loading.
- `03-new-session-dialog.png` and `04-new-session-dialog-wide.png` show the dialog while the underlying button says “Creazione…” and the dialog’s Create action is disabled. Preserve this as a captured busy state; the stable idle dialog is not confirmed.
- `11-settings-initial.png` and `12-settings-pi-cli.png` are duplicate Pi CLI views; both files are kept so the capture sequence remains auditable.
- Native OS dialogs (for example the folder picker) are outside the Flutter root render and are not represented. Review Changes requires a session with agent-authored file changes; no such fixture was produced here. The embedded browser's live navigation, terminal commands, and other listed transient dialogs were not exercised.
- A first run of the existing remote E2E script showed the host user's recent session metadata because it isolated `PI_FRAME_HOME` but not Pi's session directory. Those screenshots were discarded. The script now isolates `HOME`, `USERPROFILE`, and both Pi agent/session directories; the final screenshots came from safe reruns. No user session files or daemon config were changed.

## Remote mobile web captures

The web build was regenerated with `flutter build web --release --no-web-resources-cdn --pwa-strategy=none`. Screenshots were captured through the remote-pairing HTTPS path using the real daemon and Flutter Web app, in Playwright WebKit with touch enabled. The full remote E2E flow passed **16/16 checks** on each profile.

| Folder | Emulated profile | Full-screen viewport | Screenshot pixels |
|---|---|---:|---:|
| [`web/iphone-12/full-screen/`](web/iphone-12/full-screen/) | Playwright iPhone 12, full-screen app viewport with touch | 390×844 CSS, DPR 3 | **1170×2532** |
| [`web/iphone-18/full-screen/`](web/iphone-18/full-screen/) | iPhone 18 Pro display profile, full-screen app viewport with touch | 402×874 CSS, DPR 3 | **1206×2622** |

Each device folder also has a `viewport/` subfolder with the earlier WebKit-visible viewport crops: iPhone 12 390×664 CSS (1170×1992 pixels) and iPhone 18 Pro profile 402×681 CSS (1206×2043 pixels). Use `full-screen/` when you need the exact native pixel dimensions and aspect ratio; use `viewport/` to inspect the visible browser page area without Safari chrome.

**iPhone 18 profile caveat:** Playwright has no iPhone 18 device descriptor. Apple lists iPhone 18 Pro at 2622×1206; divided by 3 this is 874×402 logical points. The run uses Playwright's iPhone 17 Pro WebKit descriptor with its viewport expanded to the full 402×874 screen geometry. Its user-agent/OS version remains the 17 Pro descriptor, so this is a responsive-layout emulation, not an actual iPhone 18 Safari run. Apple specs: <https://www.apple.com/iphone-18-pro/specs/>.

Both device folders contain matching states. The paired workspace uses only an isolated fake Git fixture and fake-pi. App locale is Italian.

| State | iPhone 12 full-screen | iPhone 18 Pro profile full-screen |
|---|---|---|
| Unpaired/re-pair screen | [A-unpaired.png](web/iphone-12/full-screen/A-unpaired.png) | [A-unpaired.png](web/iphone-18/full-screen/A-unpaired.png) |
| Paired welcome | [B-paired.png](web/iphone-12/full-screen/B-paired.png) | [B-paired.png](web/iphone-18/full-screen/B-paired.png) |
| New-session dialog | [B1-new-session-dialog.png](web/iphone-12/full-screen/B1-new-session-dialog.png) | [B1-new-session-dialog.png](web/iphone-18/full-screen/B1-new-session-dialog.png) |
| Filled working directory | [B2-new-session-filled.png](web/iphone-12/full-screen/B2-new-session-filled.png) | [B2-new-session-filled.png](web/iphone-18/full-screen/B2-new-session-filled.png) |
| Active workspace | [B3-workspace.png](web/iphone-12/full-screen/B3-workspace.png) | [B3-workspace.png](web/iphone-18/full-screen/B3-workspace.png) |
| Composer draft | [B4-composer-draft.png](web/iphone-12/full-screen/B4-composer-draft.png) | [B4-composer-draft.png](web/iphone-18/full-screen/B4-composer-draft.png) |
| Fake-pi assistant reply | [B5-chat-response.png](web/iphone-12/full-screen/B5-chat-response.png) | [B5-chat-response.png](web/iphone-18/full-screen/B5-chat-response.png) |
| Sessions drawer | [B6-sessions-drawer.png](web/iphone-12/full-screen/B6-sessions-drawer.png) | [B6-sessions-drawer.png](web/iphone-18/full-screen/B6-sessions-drawer.png) |
| Settings | [B7-settings.png](web/iphone-12/full-screen/B7-settings.png) | [B7-settings.png](web/iphone-18/full-screen/B7-settings.png) |
| File pane | [B8-file-pane.png](web/iphone-12/full-screen/B8-file-pane.png) | [B8-file-pane.png](web/iphone-18/full-screen/B8-file-pane.png) |
| Git Changes | [B9-git-changes.png](web/iphone-12/full-screen/B9-git-changes.png) | [B9-git-changes.png](web/iphone-18/full-screen/B9-git-changes.png) |
| After daemon restart | [D-after-restart.png](web/iphone-12/full-screen/D-after-restart.png) | [D-after-restart.png](web/iphone-18/full-screen/D-after-restart.png) |
| Touch alignment (the coordinate probe leaves the new-session field focused) | [E-after-taps.png](web/iphone-12/full-screen/E-after-taps.png) | [E-after-taps.png](web/iphone-18/full-screen/E-after-taps.png) |
| Offline panel | [G-offline.png](web/iphone-12/full-screen/G-offline.png) | [G-offline.png](web/iphone-18/full-screen/G-offline.png) |

These captures exercise the responsive web UI and remote pairing flow, but cannot reproduce physical iOS Safari's address/keyboard viewport, hardware keyboard, GPU, camera, or device-specific safe-area behavior. Use a real iPhone before release. Flutter widget tests can set logical view metrics (see `apps/pi_frame/test/iphone_layout_test.dart`), but those are not substitutes for browser/WebKit captures.

## Route model

`apps/pi_frame/lib/app/router.dart` registers one GoRouter route: `/` → `AppShell`. Most navigation is shell state, not a URL route. `AppShell` selects the welcome, active workspace, or settings body from `activeSessionIdProvider`, `showSettingsProvider`, and review/pane providers (`apps/pi_frame/lib/app/app_shell.dart`).

```text
/ → AppShell
  ├─ no active session → Welcome
  ├─ active session → Workspace
  │   ├─ Sessions rail/drawer
  │   ├─ Repository pane
  │   ├─ Chat: transcript + composer + optional side conversation
  │   └─ Companion: Git Changes | Web Browser | Review Changes
  └─ Settings → one of 10 tabs → back to previous shell state
```

### Main transitions

| From | Action | To / state |
|---|---|---|
| Welcome | New session button | Working-directory dialog → active session workspace |
| Welcome / workspace | Browse sessions, header menu, or shortcut | Sessions rail/drawer; choose a session to open its workspace |
| Any shell state | Settings button | Settings view; back arrow returns to conversation/workspace |
| Workspace | Companion selector/tab | Git Changes, Web Browser, or Review Changes in the right pane |
| Workspace | Command palette action “Show Web Browser” | Web Browser companion |
| Workspace | Review changes button (available when eligible changes exist) | Review Changes replaces the Git companion; pane/sidebar layout is restored on exit |
| Workspace | Model/context toolbar action | End drawer with model, thinking, context size, reserve, compaction, clone, and session tree controls |
| Workspace | `Ctrl/Cmd+Shift+B` | Toggle read-only side conversation |
| Any shell state | `Ctrl/Cmd+K` | Command palette |

## Workspace and responsive behavior

The active workspace is composed in `AppShell._workspace` and `workArea` (`app_shell.dart`). The workspace's three logical panes are `repository`, `chat`, and `git` (`WorkspacePane` in `features/workspace/repository_workspace.dart`). The companion pane is selected as:

- **Git Changes** by default: tracked/staged/unstaged repository status and Git actions.
- **Web Browser** when browser mode is selected and supported.
- **Review Changes** while `isReviewingChangesProvider` is true; it temporarily uses the Git slot and hides Repository.

Responsive breakpoints use Flutter viewport width:

| Viewport width | Layout |
|---:|---|
| `< 900` | Compact pane selector with `IndexedStack`; one pane shown at a time. Sessions open as a drawer. |
| `900–1439` | Chat plus one companion. If more than one companion is available, tabs sit in the companion title bar. |
| `≥ 1440` | Resizable multi-pane row using visible pane weights. |
| `≥ 1560` | Add the persistent Sessions rail. |

Pane visibility, collapse/expand, and divider drag are owned by `AppShell` (`_togglePane`, `_collapsePane`, `_expandPane`, `_resizeAdjacent`). User layout is persisted by `LayoutStore`; review mode snapshots and restores layout instead of saving its temporary arrangement. The repository pane includes the file browser/editor and can host the integrated terminal below it. The chat pane contains transcript and composer; the `AgentActivitySidecar` appears on wider layouts.

### Workspace components

| Surface | Implementation | Notes |
|---|---|---|
| Welcome | `AppShell._welcome` in `app/app_shell.dart` | New session, browse sessions, recent sessions, command shortcut hint; recent items depend on isolated home contents. |
| Sessions | `features/sessions_sidebar/sessions_sidebar.dart` | Search/filter sessions, repository groups, session actions, recent/pinned entries; compact drawer or wide rail. |
| Transcript | `features/transcript/transcript_view.dart` | User/assistant turns, tool timeline, thinking, todos, subagents, context/cost affordances, scrolling. |
| Composer | `features/composer/composer.dart` | Prompt entry, model/thinking/context pickers, attachments, review/send actions, slash/file mention menus, steer/follow-up queue. |
| Repository | `features/workspace/repository_workspace.dart` | File tree/search, editor/Markdown preview, diffs, add-to-chat, branch controls; optional integrated terminal. |
| Git Changes | `features/workspace/repository_workspace.dart` (`GitChangesPane`) | Staged and unstaged groups, stage/unstage/discard, branch switching, fetch/pull/push/sync/commit. |
| Browser | `features/browser/web_browser_pane.dart` | Tabs, address/search, navigation, bookmarks/shortcuts, send-to-chat/devtools controls. |
| Review Changes | `features/session_changes/session_changes_pane.dart` | Agent/session workspace diff list and per-file diff view; only available when eligible session changes exist. |
| Side conversation | `features/side/side_panel.dart` | Read-only separate thread, opened by the command palette or shortcut. |
| Context/model drawer | `features/context_panel/context_panel.dart` | Session model, thinking, context size/reserve, usage, compaction, clone, session branch tree. |
| Integrated terminal | `features/workspace/integrated_terminal.dart` | Embedded shell panel under Repository; configurable to use a native terminal instead. |

## Settings

`features/settings/settings_view.dart` uses a non-swipeable `TabBarView`; tabs are selected through the horizontal tab strip, not page swipes. All ten tabs were captured at desktop width.

| Tab | Screenshot | Main content |
|---|---|---|
| Pi CLI | [12-settings-pi-cli.png](12-settings-pi-cli.png) | Quick commands, custom command, output console, MCP status/manager. |
| Packages | [13-settings-packages.png](13-settings-packages.png) | Installed Pi packages and package actions. Capture remained loading under fake-pi. |
| Daemon | [14-settings-daemon.png](14-settings-daemon.png) | Endpoint/protocol status, worker idle timeout, daemon restart, notifications. |
| Appearance | [15-settings-appearance.png](15-settings-appearance.png), [23-settings-appearance-lower.png](23-settings-appearance-lower.png) | Language, theme selection/editor/import, composer submit, Nerd Stats, transcript-step grouping. |
| Privacy | [16-settings-privacy.png](16-settings-privacy.png) | Local data and telemetry/privacy statements. |
| Diagnostics | [17-settings-diagnostics.png](17-settings-diagnostics.png) | Runtime health and exportable diagnostic bundle. |
| Updates | [18-settings-updates.png](18-settings-updates.png) | Version check and automatic update preferences. |
| Terminal | [19-settings-terminal.png](19-settings-terminal.png) | Integrated/native terminal mode and native shell selection. |
| Remote | [20-settings-remote.png](20-settings-remote.png) | Opt-in remote access, tunnel provider and listener state. |
| Agents | [21-settings-agents.png](21-settings-agents.png) | Default model/thinking and subagent package configuration. |

## Dialogs, menus, and interaction states

Captured representative overlays:

- New session / working directory: [03-new-session-dialog.png](03-new-session-dialog.png), [04-new-session-dialog-wide.png](04-new-session-dialog-wide.png) (busy/disabled Create state; see caveats above).
- Command palette: [24-command-palette.png](24-command-palette.png). Open from header or `Ctrl/Cmd+K`; arrow keys move selection, Enter runs the command, Escape closes. It is presented without a dialog transition.
- Branch picker: [28-branch-picker.png](28-branch-picker.png). Search/filter branches; arrow keys and Enter choose, Escape closes. Its dialog transition is disabled.
- Git diff and commit flow: [44-git-file-diff.png](44-git-file-diff.png), [46-commit-dialog.png](46-commit-dialog.png). The commit dialog was canceled; no commit was made.
- Session tree: [31-session-tree-dialog.png](31-session-tree-dialog.png). Shows child/side branch hierarchy; empty state is represented.
- Theme editor: [22-theme-editor-dialog.png](22-theme-editor-dialog.png). Preview and edit theme tokens, then cancel/apply.
- MCP server manager: [32-mcp-manager-dialog.png](32-mcp-manager-dialog.png). Harness config has no configured MCP servers.
- Context drawer: [29-context-model-panel.png](29-context-model-panel.png).
- Model and thinking menus: [33-model-picker.png](33-model-picker.png), [34-thinking-picker.png](34-thinking-picker.png).
- Side conversation empty state: [30-side-conversation.png](30-side-conversation.png).

Other code-defined dialog/menu flows to inspect when their preconditions are available: delete session confirmation; remove repository choice and typed confirmation; rename/session actions; instruction-file dialog; repository dirty/reload conflict, branch-switch failure, file diff, discard confirmation and commit-message dialog; session info/context-size/cost views; attachment link/image preview and Copilot file picker; composer slash/file-mention/autocomplete menus; package update/remove/pin confirmation and pin-version picker; remote installation/access confirmation; Pi install and update confirmation; extension-provided select/confirm UI; side-thread close confirmation. These live mainly in `features/sessions_sidebar/`, `features/workspace/`, `features/composer/`, `features/settings/`, and `features/dialogs/`.

## Motion and animation inventory

| Motion | Code location | Trigger / behavior |
|---|---|---|
| Startup reveal and assemble | `lib/main.dart`, `ui/precision.dart` (`LaunchReveal`), `ui/startup_assemble_animation.dart` (`StartupAssembleOverlay`) | App startup reveal/assembly overlay. |
| Transcript/entry changes | `features/transcript/` | Streaming text/tool updates, grouped steps, scroll-follow and completion status; see [36-tool-call-transcript.png](36-tool-call-transcript.png), [37-thinking-transcript.png](37-thinking-transcript.png), [38-thinking-expanded.png](38-thinking-expanded.png), [39-thinking-content.png](39-thinking-content.png). |
| Composer expand/collapse | `features/composer/composer.dart` (`AnimatedSize`, switchers) | Prompt/attachment/command area changes size as content or mode changes. |
| Drop target | `features/transcript/chat_drop_target.dart` | Opacity/scale feedback while dragging files over chat. |
| Agent sidecar | `features/transcript/subagent_panel.dart` | Entrance/size changes and activity pulse. |
| Active outlines | Composer and sessions sidebar | `ShimmerBorder` around active/in-progress affordances. |
| Pane resizing | `app/app_shell.dart` | Pointer drag adjusts adjacent pane widths; state/layout transitions update visible panes. |
| Command palette / branch picker | `features/command_palette/command_palette.dart`, `features/workspace/branch_picker_dialog.dart` | Dialog transitions explicitly disabled. |
| Web navigation / terminal | `features/browser/web_browser_pane.dart`, `features/workspace/integrated_terminal.dart` | Tab and navigation state changes; shell output streams in the terminal. |
| Session/review transitions | `app/app_shell.dart` | State-driven pane replacement; review mode stores/restores prior visibility, weights, and session rail state. |

The fake-pi captures include a completed tool call and completed thinking state, plus an actual in-progress stream and its completion: [36-tool-call-transcript.png](36-tool-call-transcript.png), [37-thinking-transcript.png](37-thinking-transcript.png), [38-thinking-expanded.png](38-thinking-expanded.png), [39-thinking-content.png](39-thinking-content.png), [40-streaming-response.png](40-streaming-response.png), [41-streaming-completed.png](41-streaming-completed.png).

## Screenshot gallery / coverage index

All captures are real PNG output from the PiFrame Flutter app, not mockups. Open the linked file for full resolution.

| File | State represented | Viewport |
|---|---|---:|
| [01-welcome-wide.png](01-welcome-wide.png) | Empty welcome, wide layout | 1424×991 |
| [02-welcome-compact.png](02-welcome-compact.png) | Welcome, compact layout | 744×891 |
| [03-new-session-dialog.png](03-new-session-dialog.png) | New session dialog at compact width | 744×891 |
| [04-new-session-dialog-wide.png](04-new-session-dialog-wide.png) | New session dialog at desktop width | 1424×991 |
| [05-workspace-initial.png](05-workspace-initial.png) | New active session and repository tree | 1424×991 |
| [06-chat-transcript.png](06-chat-transcript.png) | User turn and fake-pi assistant reply | 1424×991 |
| [07-workspace-wide.png](07-workspace-wide.png) | Sessions rail and resizable multi-pane workspace | 1584×991 |
| [08-git-changes-expanded.png](08-git-changes-expanded.png) | Expanded Git Changes list | 1784×1041 |
| [09-workspace-compact.png](09-workspace-compact.png) | Compact pane tabs and chat | 744×891 |
| [10-sessions-drawer.png](10-sessions-drawer.png) | Compact sessions drawer | 744×891 |
| [11-settings-initial.png](11-settings-initial.png) | Settings Pi CLI page at desktop width | 1584×991 |
| [12-settings-pi-cli.png](12-settings-pi-cli.png) | Pi CLI tab | 1584×991 |
| [13-settings-packages.png](13-settings-packages.png) | Packages tab loading state | 1584×991 |
| [14-settings-daemon.png](14-settings-daemon.png) | Daemon tab | 1584×991 |
| [15-settings-appearance.png](15-settings-appearance.png) | Appearance, theme and language settings | 1584×991 |
| [16-settings-privacy.png](16-settings-privacy.png) | Privacy tab | 1584×991 |
| [17-settings-diagnostics.png](17-settings-diagnostics.png) | Diagnostics tab | 1584×991 |
| [18-settings-updates.png](18-settings-updates.png) | Updates tab | 1584×991 |
| [19-settings-terminal.png](19-settings-terminal.png) | Terminal settings | 1584×991 |
| [20-settings-remote.png](20-settings-remote.png) | Remote access settings/disabled state | 1584×991 |
| [21-settings-agents.png](21-settings-agents.png) | Agents/subagents configuration | 1584×991 |
| [22-theme-editor-dialog.png](22-theme-editor-dialog.png) | Theme editor overlay | 1584×991 |
| [23-settings-appearance-lower.png](23-settings-appearance-lower.png) | Appearance settings lower sections | 1584×991 |
| [24-command-palette.png](24-command-palette.png) | Command palette overlay | 1584×991 |
| [25-web-browser-pane.png](25-web-browser-pane.png) | Embedded browser home | 1584×991 |
| [26-integrated-terminal.png](26-integrated-terminal.png) | Repository with embedded PowerShell terminal | 1584×991 |
| [27-repository-file-editor.png](27-repository-file-editor.png) | Repository Markdown source editor | 1584×991 |
| [28-branch-picker.png](28-branch-picker.png) | Branch picker dialog | 1584×991 |
| [29-context-model-panel.png](29-context-model-panel.png) | Context/model end drawer | 1584×991 |
| [30-side-conversation.png](30-side-conversation.png) | Side conversation panel empty state | 1584×991 |
| [31-session-tree-dialog.png](31-session-tree-dialog.png) | Session branch tree dialog empty state | 1584×991 |
| [32-mcp-manager-dialog.png](32-mcp-manager-dialog.png) | MCP manager empty state | 1584×991 |
| [33-model-picker.png](33-model-picker.png) | Composer model picker | 1584×991 |
| [34-thinking-picker.png](34-thinking-picker.png) | Composer thinking-level picker | 1584×991 |
| [35-workspace-light-theme.png](35-workspace-light-theme.png) | Active workspace in light theme | 1584×991 |
| [36-tool-call-transcript.png](36-tool-call-transcript.png) | Completed tool-call transcript | 1584×991 |
| [37-thinking-transcript.png](37-thinking-transcript.png) | Thinking step grouped/collapsed | 1584×991 |
| [38-thinking-expanded.png](38-thinking-expanded.png) | Thinking group expanded | 1584×991 |
| [39-thinking-content.png](39-thinking-content.png) | Thinking text expanded | 1584×991 |
| [40-streaming-response.png](40-streaming-response.png) | Real in-progress fake-pi streaming response | 1584×991 |
| [41-streaming-completed.png](41-streaming-completed.png) | Streaming response completed | 1584×991 |
| [42-git-fixture-workspace.png](42-git-fixture-workspace.png) | Clean controlled Git fixture with staged + unstaged changes | 1784×1041 |
| [43-git-staged-and-unstaged.png](43-git-staged-and-unstaged.png) | Expanded staged and unstaged file groups | 1784×1041 |
| [44-git-file-diff.png](44-git-file-diff.png) | Selected-file unified diff overlay | 1784×1041 |
| [45-staged-changes.png](45-staged-changes.png) | Both fixture files staged; empty unstaged state | 1784×1041 |
| [46-commit-dialog.png](46-commit-dialog.png) | Commit message dialog; canceled without committing | 1784×1041 |

## Useful source map for a future UI agent

- Route and shell orchestration: `apps/pi_frame/lib/app/router.dart`, `apps/pi_frame/lib/app/app_shell.dart`.
- Theme, colors, radii, typography: `packages/pi_frame_theme/`, `apps/pi_frame/lib/ui/`, and `docs/theming.md`.
- Settings pages: `apps/pi_frame/lib/features/settings/settings_view.dart` and sibling `*_section.dart` widgets.
- Transcript and motion: `apps/pi_frame/lib/features/transcript/`, `apps/pi_frame/lib/features/composer/composer.dart`.
- Repository/Git/editor/browser/terminal: `apps/pi_frame/lib/features/workspace/`, `features/browser/`, `features/session_changes/`.
- Sessions and creation actions: `apps/pi_frame/lib/features/sessions_sidebar/`, `features/session_tree/`.
- Existing widget and behavior tests: `apps/pi_frame/test/`; use targeted tests before full `flutter test`.
- Real UI driving and screenshots: `.agents/skills/piframe-ui-harness/SKILL.md`, `tools/harness/README.md`. Start with `pnpm harness start`, inspect with `tree`, use stable keys, save PNGs with `pnpm harness shot`, and always stop with `pnpm harness stop`.
