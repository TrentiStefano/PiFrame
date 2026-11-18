# Troubleshooting and Known Issues

This document collects diagnoses, root causes and fixes for known problems in the **PiFrame** desktop and web runtime.

---

## Path links open the wrong WSL distro on Windows

**Symptom:** on Windows, clicking a Linux path in the chat (for example `/home/user/repo/lib/main.dart`) in a session whose folder is not a WSL UNC path tried to open it in a fixed WSL distro name that existed only on the developer's machine, so File Explorer showed nothing or the wrong folder.

**Cause:** `resolvePathForOsExplorer` in `rich_content.dart` built `\\wsl.localhost\<fixed distro>\…` for every pure Linux path, and the `wslpath` fallback in `openInOsFileExplorer` did not run for Linux working folders with relative links.

**Fix:** a pure Linux path with no known distro now stays a Linux path, and `openInOsFileExplorer` maps it with `wsl.exe wslpath -w`, which uses the default distro. The fallback also runs when the session folder is a Linux path. Paths inside a WSL UNC folder (`\\wsl.localhost\<distro>\…` or `\\wsl$\<distro>\…`) keep using that folder's distro.

Check from source (Windows):

```bash
cd apps/pi_frame
flutter test test/transcript_rich_test.dart
```

---

## Agents pane reopens on close, and Git Changes cannot be expanded, while a subagent runs

**Symptom:** while a subagent was working, clicking the Agents pane collapse button closed it and reopened it at once. Expanding the Git Changes pane collapsed it again straight away.

**Cause:** `AgentSidecarLayout` placed the sidecar in a `Row` beside the chat, but in a `Stack` overlay when the chat was narrower than 420 px. Closing the panel, or expanding Git (which narrows the chat), switched between the two, so Flutter remounted the sidecar. On mount, its listeners fire immediately: "agents are running" reopened the panel, and "panel open" asked the shell to collapse Git.

**Fix:** the sidecar layout now uses one `CustomMultiChildLayout` for both modes, so chat and sidecar stay mounted when it switches. The automatic open also happens once per running episode (tracked in a provider, not in the widget), so a panel closed while the same agents still run stays closed.

Check from source:

```bash
cd apps/pi_frame
flutter test test/subagents_feature_test.dart test/overflow_widths_test.dart
```

---

## Subagents and workflows stuck as "running"

**Symptom:** a background subagent or workflow stayed "In progress" for hours. Stopping it from the Agents pane showed it as stopped, but the main agent could not confirm it, and it was marked running again after a restart.

**Cause:** a background `Agent` launch counts as running until its `<task-notification>` reaches the parent session. When the notification never arrives (for example, the Pi worker was restarted or the agent died), the daemon reported it as running forever. Workflow runs had the same problem. The Stop button only sends a stop request to the main agent and marks the agent stopped locally, so the daemon's status came back after a reload.

**Fix:** `SessionIndex.getSubagents` now falls back to the child session file for a background agent with no notification: a final answer marks it completed, and 10 minutes without writes marks it settled (the same rule already used for unlinked child sessions). In the app, `settleIdleWorkflows` marks a workflow run completed when all its agents settled and none wrote for 10 minutes. A run with no agents to judge by stays running.

Check from source:

```bash
cd apps/agentd && pnpm build && node --test dist/test/sessionCostPersistence.test.js
cd apps/pi_frame && flutter test test/workflows_provider_test.dart
```

---

## Chat jumps back to the bottom while the agent answers

**Symptom:** while the agent streamed the first answer of a turn, scrolling up in the chat did not stick: every streaming update pulled the view back to the bottom.

**Cause:** the answer-based windowing change reset the "user scrolled up" flag on every rebuild whose last entry was a user message. While the agent answers, the prompt is still the last committed entry, so each update re-enabled auto-follow.

**Fix:** `transcript_view.dart` tracks the entry count and resets the flag only when a new user message arrives. Sending a message still scrolls to the bottom; reading earlier messages during a run is no longer interrupted.

Check from source:

```bash
cd apps/pi_frame
flutter test test/transcript_scroll_test.dart
```

---

## Chat history windowing by agent answers, and a card border shown too early while running

**Symptom:**
1. In turns with many intermediate steps or tool calls (for example 20 or more), the user prompt was unloaded and hidden from the chat window, so you had to click «Load earlier messages» again and again. The pagination limit counted raw messages (tools and intermediate steps included).
2. While the agent was working between tool calls, or while streaming, the last temporary message was shown with the card border (`isCard: true`) as if it were the final answer, then lost the border when the agent continued.

**Cause:**
1. `_visibleCount` used a raw threshold (35 messages at first) that counted tool calls, results and grouped intermediate steps alike. If a single turn produced 40 log or tool entries, the user prompt above them fell outside the visible window. Pagination also grew by a raw number of entries instead of by turns or agent answers.
2. In `transcript_grouping.dart`, detection of the last answer block (`finalAssistantEntry`) did not check whether the current turn was still running (`turn.isLastTurn && live.isRunning`), and `LiveTailBlock` in `transcript_view.dart` always set `isCard: true`.

**Fix:**
1. Chat history windowing in `transcript_view.dart` now counts the last **10 agent answers** (`_visibleAnswerCount = 10`), ignores grouped intermediate steps (tool call, tool result, thinking) in the count, and never unloads the user prompt of a loaded turn. Pagination with «Load earlier messages» moves in blocks of 10 complete answers.
2. In `transcript_grouping.dart`, no intermediate message is promoted to final answer (`finalAssistantEntry`) while the turn is running (`live.isRunning`). Intermediate messages are emitted as `IntermediateTextBlock` (`isCard: false`) and the live `LiveTailBlock` also keeps `isCard: false`: only when the turn really ends is the final message shown with the card border (`FinalTextBlock`, `isCard: true`).

Check from source:

```bash
cd apps/pi_frame
flutter test test/transcript_history_window_test.dart test/transcript_grouping_test.dart
```

---

## Long Git branch names truncated in the branch picker and in the Git Changes header

**Symptom:** Git branches with long names (for example `Sprint_2026_21/Sprint_Login_Refactor_Phase1`) were truncated with an ellipsis both in the branch picker dialog (`BranchPickerDialog`) and in the current-branch pill of the Git Changes header, which made them unreadable.

**Cause:** `BranchPickerDialog` had a fixed maximum width of only 540 px and forced the branch name and its upstream onto the same line in very narrow fixed columns (upstream limited to 150 px). In the Git Changes pane, the branch pill had a hard `maxWidth: 160` that stopped the name from growing even with plenty of horizontal space.

**Fix:** `BranchPickerDialog` is now 740 px wide (adapting on compact displays) and its rows have two levels: the main line shows the icon, the full branch name (with all the space available), the ahead/behind sync indicators and the current-branch badge; a second, subordinate line shows the upstream (`origin/...`) clearly. In the Git Changes pane, the branch pill uses an adaptive `LayoutBuilder` that allows up to 65% of the pane width (or a dedicated line when the pane is very narrow) and shows the full branch name in a hover tooltip.

Check from source:

```bash
cd apps/pi_frame
flutter test test/branch_browser_test.dart
```

---

## /side and /btw window not visible, and handling of a session's side discussions

**Symptom:** running `/side` or `/btw` from the composer did not open the window or did not work; earlier side discussions of the session were neither stored nor navigable.

**Cause:** `SideSplit` was wrapped only around the `TranscriptView` inside the chat column (above the composer), so it collapsed to zero width or collided with the minimum widths of the split layout. The state also kept only one short-lived thread per session, with no history and no way to move between several discussions.

**Fix:** side discussions (`/side` and `/btw`) are now a dedicated side pane (`SidePanel`) inside the chat's companion sidecar (`AgentActivitySidecar` / `AgentSidecarLayout`), next to the chat like the Agents pane. `side_provider.dart` keeps a `SideConversationRecord` history of every side discussion in the session, with a pill selector to move between active and finished discussions, a `+` button to open new side questions, and continuous sync of messages and the mini composer.

Check from source:

```bash
cd apps/pi_frame
flutter test test/side_conversation_test.dart
```

---

## Flicker while resizing panes, and chained expansion of step groups

**Symptom:** while collapsing or expanding side panes (for example sessions, Git or repository), the other open panes disappeared for about a second, causing an annoying flicker; clicking the header of a compact step group also expanded every group above and below it.

**Cause:** in the main shell (`app_shell.dart`), the `_entryAlpha` opacity calculation wrongly treated already-open panes that were widening as "new entries" and set their opacity to zero for 60% of the transition. For compact steps, expansion state was stored by turn ID (`turnId`) instead of the unique ID of each compact block (`groupId`), so every group in the same turn opened together.

**Fix:** `_entryAlpha` lowers opacity only for panes that were actually closed (`fromPx <= 40`), keeping full opacity and a smooth transition on every pane already visible. In `step_group_expansion.dart` and `steps_group.dart`, the override key now stores the block's own `groupId`, so each step group expands and collapses independently.

Check from source:

```bash
cd apps/pi_frame
flutter test test/steps_group_widget_test.dart
```

---

## Step grouping with intermediate reasoning, and subagent notifications

**Symptom:** with step grouping set to "with thinking" (`withThinking`), turns with tool calls and intermediate answers or reasoning appeared loose in the chat instead of grouping compactly; subagent notifications also produced large cards that cluttered the conversation history.

**Cause:** `StepGroupingMode.withThinking` only checked for explicit `<thinking>` blocks. When the model emitted reasoning text followed by tool calls, the condition was not met. The `<task-notification>` XML notifications were also rendered as full-width `custom` messages with a double border, instead of being summarized as compact steps of the turn.

**Fix:** `transcript_grouping.dart` now treats intermediate reasoning text before or between tools as agent thinking. A `showIntermediateAnswers` preference was added to `StepGroupingSettings` and the appearance settings; it shows borderless intermediate reasoning steps between consecutive compact groups and puts the final answer in its own bordered card. Subagent completion notifications are compacted as `SubagentNotificationStep` inside the step group, while the full tree and cost details stay in the Agents tab of the right sidebar.

Check from source:

```bash
cd apps/pi_frame
flutter test test/transcript_grouping_test.dart test/subagents_feature_test.dart
```

---

## Overflow stripes in the companion, todo, cards and Agents pane at narrow widths

**Symptom:** with a narrow chat or the Agents pane open, the browser bar, the todo pane, activity cards, the assistant header and the composer chips showed yellow-and-black stripes (in debug) or were cut off (in release). The model chip ended up under the expand icon.

**Cause:** bars and headers had fixed widths or non-flexible children. The Agents pane took about 360 px and left the chat too little room.

**Fix:** a companion (Git, files or browser) narrower than 160 px (`kCompanionMinWidth`; 320 px before the UI rework) shrinks to its side tab instead of squeezing the bar. A narrow browser moves Home and bookmarks into the bar's menu. The Agents pane becomes a sheet above the chat when it would leave the chat under 420 px; the sheet stops above the composer, so send and the model stay reachable. Todo, activity cards and the assistant header use flexible layouts and wrapping text. The composer chips shorten their labels as space shrinks.

Check from source:

```bash
cd apps/pi_frame
flutter test test/overflow_widths_test.dart
```

---

## Questions with previews too tall for the window

**Cause:** the RPC fallback of `rpiv-ask-user-question` puts every preview in the request title. PiFrame showed the title outside the scrollable area, pushing the answers out of the window.

**Fix:** PiFrame recognizes RPC preview blocks and shows only the one of the selected option. Use the mouse or the up/down arrows to change the choice; in narrow windows the preview appears below the options. The answers sent to Pi do not change. A long, unrecognized title is now scrollable too.

The package limits each RPC preview to its first 600 characters: PiFrame cannot show text the package did not send. To apply the change, rebuild and restart the app.

Check from source:

```bash
cd apps/pi_frame
flutter test test/extension_ui_card_test.dart test/extension_ui_test.dart
```

---

## Repeated package notice, and versions that do not advance

**Symptom:** the extensions notice comes back at startup; after an update the page reports success but may still show the previous version.

**Causes fixed:** the startup check compared the dependencies reported by `npm outdated` with `latest`, without following the sources configured in Pi or pinned versions. Updates were treated as successful from the exit code alone, without checking the installed manifests, and did not reload the notice state. Cached npm metadata could also leave an older version even when the command did not fail.

**Fix:** the check and the update use the user packages listed by the daemon and resolve the version the npm source expects, honoring ranges, tags and pins. npm requests prefer fresh metadata; after installation the actual version must reach the expected one, otherwise an error shows the installed and expected versions. The summary separates updated, already current and pinned packages. The notice is recalculated after updates, removals and pins. Network or package-manager errors are not turned into "no updates".

**Platform incompatibility:** an npm `EBADPLATFORM` error can concern a required dependency, even when the extension declares no restriction. For example `@hypabolic/pi-hypa@1.2.0` needs `@hypabolic/hypa@1.2.0`, available only on macOS and Linux. PiFrame first checks the installation with a dry run that runs no scripts, shows the reason on the Packages page and does not offer that version as an installable update. On Windows, version `0.1.15` of the extension can be installed and pinned with **Pin version**, after checking its compatibility. Pinning is explicit: PiFrame does not force incompatible versions and does not change the configured source automatically.

This fix needs both an updated app and an updated daemon. A daemon that is already running keeps running the old code: restart it from **Settings → Daemon** only after the Pi workers have finished. The code of updated extensions loads the next time Pi starts; you do not need to delete packages or settings.

---

## Background subagents shown as completed

**Symptom:** the card showed "Completed" at once, even though the subagent was still running or queued.

**Cause:** the return of the `Agent` call and the end of the main session were mistaken for the end of the subagent.

**Fix:** a background start stays active until a notification or a terminal result arrives. Slow daemon answers are no longer discarded after four seconds. If the daemon never answers, the metadata does not update until the request resolves. Rebuild and restart the app to apply the change.

---

## Duplicate subagents, or subagents with unavailable cost

**Symptom:** a call that read a result, or a completion notification, appeared as another subagent. The child session, shown with a name such as `reviewer#...`, could have a cost separate from the original call.

**Fix:** PiFrame links the `Agent` call to the child session through the identity available and shows the task name, the recorded cost and the effective model. Notifications update a known agent instead of creating a new one. Unavailable data stays `N/A`; estimates and arbitrary text never become real costs. If a link is ambiguous, the child session stays visible as unattributed, without an extra agent card.

The cost reported by Pi and the costs of attributed subagents are shown separately: Pi may already include the latter in the former. The attributed total is marked as partial when data is missing; the costs of unattributed sessions stay separate.

To apply a daemon change, rebuild it together with the app and restart the daemon only when no Pi worker is active. Building only the app does not update a daemon that is already running.

---

## Error "$ pi update --all /bin/sh: pi: command not found [code 127]"

**Symptom:** running a Pi command from *Settings → Pi CLI* (for example `pi update --all`), or starting the automatic installation on macOS, ended at once with:
```
$ pi update --all
/bin/sh: pi: command not found

[Process completed with code 127 in 24ms]
```
Also, even after Pi had been installed separately in Terminal, the app still reported that Pi was not installed.

**Root cause:**
On macOS, GUI apps started by Launch Services (Finder, Dock, Spotlight) inherit from `launchd` a minimal `PATH` of `/usr/bin:/bin:/usr/sbin:/sbin`. Executables installed by the official curl script (`~/.local/bin/pi`), Homebrew (`/opt/homebrew/bin/pi` or `/usr/local/bin/pi`) or Node version managers (`~/.nvm/...`) are not on those paths, and non-interactive shells started by `/bin/sh` do not load the user's `.zprofile` or `.zshrc`.

**Fix:**
1. A central `PlatformEnvironment` module, in both the Flutter client and the `agentd` daemon, extends `PATH` with `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/share/pi-node/current/bin` and the app bundle folder, and also queries the user's login shell.
2. Pi commands first resolve the absolute path of the `pi` executable and run the process with the extended environment, without depending on the default `/bin/sh` path.
3. PiFrame's built-in installer now runs the official `curl -fsSL https://pi.dev/install.sh | sh` (or `irm https://pi.dev/install.ps1 | iex` on Windows) and sets up the prerequisites (standalone Node.js or Homebrew) when they are missing.

---

## macOS Gatekeeper: unsigned or unverified app blocked

**Symptom:** opening `PiFrame.app` on macOS shows *"The application cannot be opened because Apple cannot check it for malicious software"*, or it does not start unless you give explicit consent.

**Root cause, and why it is not free:**
macOS applies Gatekeeper to every file and executable downloaded from the Internet (adding the extended attribute `com.apple.quarantine`). To start an app immediately without security warnings, Apple requires a paid **Apple Developer Program** membership ($99 USD a year), a *Developer ID Application* certificate and notarization through Apple's servers (`xcrun notarytool`).
Apple offers no free official way to sign and notarize apps for public distribution (free Apple accounts only create local development profiles valid for 7 days on registered devices).

PiFrame applies an ad hoc signature (`codesign --force --deep --sign -`) in the GitHub Actions release workflow, which meets the mandatory signing requirement of Apple Silicon (`arm64`).

**Fix:**
1. **GUI option (macOS 14 Sonoma and macOS 15 Sequoia):**
   - Double-click `PiFrame.app`. If the Gatekeeper warning appears, press *Cancel* or close the dialog.
   - Open **System Settings → Privacy & Security**.
   - Scroll down to **Security**.
   - You will see *"PiFrame was blocked from use..."*: click **Open Anyway** and enter your password or use Touch ID.
2. **Terminal option (one command):**
   ```bash
   xattr -cr /Applications/PiFrame.app
   ```
   This recursively clears the `com.apple.quarantine` attribute from the app bundle. From then on, PiFrame starts with a normal double-click.

---

## Pi built-in commands missing from the menu or sent to the model

**Cause:** the RPC command `get_commands` returns extension, prompt and skill commands, but not the built-in catalog of the Pi TUI. The composer also sent all text as a prompt, so an unhandled TUI command could be treated as text for the model.

**Current behavior:** the `/` menu includes Pi's built-in catalog (`settings`, `model`, `tree`, `thinking`, `scoped-models`, `export`, `import`, `share`, `bug`, `copy`, `name`, `session`, `changelog`, `hotkeys`, `fork`, `clone`, `trust`, `login`, `logout`, `new`, `compact`, `resume`, `reload`, `quit`) together with the RPC commands of extensions, prompts and skills. In PiFrame, `/settings`, `/model`, `/tree`, `/thinking`, `/new`, `/compact`, `/reload`, `/copy`, `/name`, `/session`, `/fork`, `/clone`, `/resume` and `/quit` have local actions. The other built-ins are recognized and show a message: they are not forwarded to the model, because they need TUI UI or APIs the RPC worker does not expose.

`/reload` calls `ctx.reload()` through an internal PiFrame command and then reapplies the context policy. It is refused while an answer or a compaction is running. The catalog mirrors Pi's built-in list; update it when Pi adds or removes commands.

Daemon check:

```bash
pnpm --filter @piframe/agentd exec tsc --outDir .temp/builtin-command-tests
node --test apps/agentd/.temp/builtin-command-tests/commands/test/SlashReload.test.js
```

The test uses a simulated worker; it does not test the UI actions or the reload against a real Pi session. After updating the daemon and the app, check the `/` menu and try the commands in a test session.

---

## Review Changes: wrong counts and diffs

**Causes fixed:** the pane added `+1/-0` to every file Pi touched, even when Git did not report it as changed; for a clean tracked file the `--no-index` fallback showed the whole file as added. Untracked files had no counts, and renames with paths containing spaces or special characters were not matched.

**Current behavior:** Review uses only the daemon's Git list. The counts are the net lines `HEAD` → working tree (staged and unstaged included), also for untracked files and for a repository without `HEAD`. A clean or missing file does not produce a fake diff; a loading error is shown as an error, not as "no differences". Binary files count zero and keep Git's binary diff.

Check from source:

```bash
pnpm --filter @piframe/agentd exec tsc --outDir .temp/bugfix-tests
node --test apps/agentd/.temp/bugfix-tests/workspace/test/gitClient.test.js
cd apps/pi_frame
flutter test test/session_changes_review_test.dart
```

---

## Duplicated input or wrong characters in the integrated terminal

**Symptom:** some keys appear twice, or Unicode characters come out wrong.

**Cause:** unhandled key-release events could fall through to xterm's text-insertion fallback. Each stdout/stderr chunk was also decoded as UTF-8 on its own: a multibyte character split across two chunks could be corrupted.

**Fix:** PiFrame consumes key-release events, handles key repeat, iterates input by code point and decodes stdout/stderr as a UTF-8 stream. The terminal already uses the active theme's color tokens.

## PowerShell command echoed and output indented

**Symptom:** on Windows the command appears a second time under the prompt and the output starts shifted to the right.

**Cause:** PiFrame shows input as you type. PowerShell, started with stdin/stdout connected to pipes instead of a terminal, also echoes the command; its echo ends with `LF` without `CR`. xterm moves to the next line without returning the cursor to column zero, and the output inherits the command's offset.

**Fix:** PiFrame recognizes the echo of the command it already showed locally, including its `LF`, and removes it from stdout. Results start at column zero again.

---

## `/agents` → Workflows reopens the Agents menu

**Symptom:** in the `/agents` menu you choose **Workflows (1)** and press **Send**; the **Agents** question comes back at once.

**Cause:** with a single workflow, `@tintinweb/pi-subagents` opens a custom TUI view (`ctx.ui.custom()`). Over RPC this view does not exist and returns `undefined` at once, so the extension shows the main menu again.

**Fix:** PiFrame recognizes the **Workflows (N)** choice in the Agents menu, cancels the request and opens its own **Agents** pane, which shows workflows and subagents. The extension is not changed.

---

## Agents pane: finished agents shown as "Running" and Git not minimized

**Symptoms:**
- agents that had finished stayed "Running";
- workflow child sessions appeared as file names, with no hint of what they do;
- entering a session with the Agents pane already open left Git Changes expanded.

**Causes:**
- the daemon read only the first `<task-notification>` of each message and ignored the `subagents:record` records that pi-subagents saves when an agent ends;
- child sessions without a linked `Agent` call had neither state nor activity;
- Git was minimized only on the closed → open transition, not when the pane was already open on entering the session;
- a `session.subagents` request that never got an answer blocked every later update.

**Fix:**
- the daemon reads every notification and final record;
- for each child session it derives type, task, current activity, start and last update; a child session idle for 10 minutes is considered finished;
- the pane minimizes Git also when it is already open on entering the session;
- daemon requests time out after 30 seconds.

The daemon fixes apply only after it is updated and restarted.

---

## Slow Repository and Git panes

**Symptom:** opening or refreshing the Repository/Git panes and loading a diff can be slow in repositories with many untracked files.

**Cause:** a single file's diff requested the full status with every count, which counted untracked files by starting one Git process per file, in sequence. Loading the Repository pane also resolved the real path of every file, even when many files shared a folder.

**Fix:** untracked-file counts are processed in limited batches; the diff requests a status scoped to the path, keeping the full check when a staged rename has to be recognized. Repository loading reuses the canonical folder resolution.

---

## Hidden panes visible again after a restart

**Cause fixed:** pane visibility and the sessions pane lived only in memory, so every launch started from the default layout.

**Current behavior:** PiFrame saves in `~/.piframe/layout.json` which panes are hidden and whether the sessions sidebar is collapsed. During Review Changes the user's layout is saved, not the temporary one. A damaged file is ignored and the default layout is restored.

Check from source:

```bash
cd apps/pi_frame
flutter test test/layout_persistence_test.dart
```

---

## Chat input lags when panes are widened

**Cause:** while a divider was dragged, the composer was inside an `AnimatedSize` meant for minimize and expand. Every size change during the drag could be animated, so the composer followed the divider late.

**Current behavior:** while a divider is dragged, the composer follows the pane size at once. Minimize/expand keeps its 280 ms animation.

---

## Window opens at the top left and the maximized state is lost

**Causes fixed:** at startup Dart restored the saved position, so a window could open in a corner. On Windows the first `Show()` used `SW_SHOWNORMAL`, which undid the maximization that had just been applied.

**Current behavior:** the window opens centered with the saved normal size. If it was maximized or full screen, that state is restored; the normal size is not replaced by the maximized one. The final state is saved before closing. The first launch without a saved file uses the default size, centered.

Check from source:

```bash
cd apps/pi_frame
flutter test test/window_restore_test.dart test/startup_animation_and_window_test.dart
```

Check the Windows release after an explicit release build: this test does not start the native window.

---

## Command timer reset on session switch, and misleading timeouts

**Causes fixed:** the timer started when the widget was mounted. Switching sessions recreated the widget and reset the count to zero. The UI also read any timeout above 1000 as milliseconds, mistook `WaitMsBeforeAsync` for a deadline and applied the first command's timeout to the whole turn.

**Current behavior:** the daemon keeps the start times of turns and commands and includes them in events and snapshots. Switching sessions or recreating a card does not change the timer's origin. The duration stops on completion or Stop; the executor's duration is used when available, otherwise the time observed by the daemon. For older snapshots without start times, no new start is invented.

The timeout appears only on the single action and shows the value requested in its arguments. `timeout`/`timeoutSeconds`/`timeout_seconds` are in seconds, `timeoutMs`/`timeout_ms` in milliseconds; explicit `s` and `ms` suffixes are honored, fractional values included. `WaitMsBeforeAsync`, invalid values and missing fields do not create a limit. The timeout is not applied to the whole message or turn.

In **Pi's built-in bash** tool the timeout is optional, in seconds, with no default. The daemon's RPC timeout is about the acknowledgement, not the command's duration. Other tools or extensions may have their own limits: PiFrame imposes no new timeout and does not guess defaults it was not told about.

Check from source, without rebuilding the Windows release:

```bash
cd apps/pi_frame
flutter test test/tool_timer_state_test.dart test/message_seconds_counter_test.dart test/tool_card_expanded_command_test.dart
```

---

## Sessions not loaded at startup

**Observed causes:** the provider could miss the connection notification because it subscribed to events after reading the initial state. The daemon also scanned session files synchronously and, with a cold cache, read their full content before answering. If the scan took more than 8 seconds, the client showed a timeout.

**Fix:** the provider watches the connection before reading the state and shows errors instead of presenting them as an empty list. For the first list, the daemon reuses cached metadata and reads limited parts of the files; it completes the index in the background and notifies the UI during and after the update. Older indexes without a metadata modification date are checked again in the background. Indexing does not change session files. If a title is missing or stale in the cache, the ID or the previous title may show for a while, because Pi can record a rename anywhere in the file. If a file changes while it is read, it is checked again after a growing interval. The time depends on the number of files and the speed of the file system.

Check from source, without starting the app:

```bash
pnpm --filter @piframe/agentd exec tsc --outDir .temp/startup-tests
node --test apps/agentd/.temp/startup-tests/sessions/test/FastSessionStartup.test.js
cd apps/pi_frame
flutter test test/daemon_state_test.dart
```

---

## Duplicate tool blocks during an answer

**Cause:** Pi sends a tool call in the assistant message and then in the execution events. The chat showed both; in some cases the call was also copied into the next message.

**Fix:** the chat reconciles calls by `toolCallId`, keeping state, output and duration up to date. Distinct calls stay visible, and calls already recorded are not added again at the end of the turn. This also holds for snapshots loaded during a run.

Check from source, without rebuilding the Windows release:

```bash
cd apps/pi_frame
flutter test test/transcript_message_types_test.dart test/session_tool_history_test.dart
```

---

## Agent actions missing after Stop or when the chat reopens

**Cause fixed:** the chat parsers recognized only `tool_call` and `tool_use`, not Pi's `toolCall` format with its arguments in `arguments`. When the history was rebuilt, the reasoning stayed but the edit/write/bash/todo cards disappeared. Outputs saved as text blocks in `toolResult` messages were not restored either.

**Current behavior:** live messages, snapshots and history loading also recognize Pi's format, keeping arguments, outputs and errors. Stop does not remove actions already recorded. Existing sessions need no migration: the cards are rebuilt from the original messages, if they are still in the session file.

Check from source, without rebuilding the Windows release:

```bash
cd apps/pi_frame
flutter test test/session_tool_history_test.dart test/session_reducer_test.dart test/transcript_message_types_test.dart
```

---

## Subagent cost always zero, or frozen in the popup

**Causes fixed:** the daemon read `usage.cost` only on the JSONL container, ignoring `message.usage.cost` in Pi messages. It also discarded every session with a temporary working directory, including the persistent sessions of subagents that use a worktree. The notification parser did not recognize the pi-subagents tag `<estimated_cost_usd>`. The refresh could stop because workers outside the daemon were already reported as completed, and the cost popup kept the values present when it opened.

**Current behavior:** the daemon sums the costs saved in both forms, also as the session file grows, without counting the same entry twice. It also reads persistent child sessions in temporary worktrees, without adding them to the normal session list; the parser recognizes the estimated cost emitted by pi-subagents. Cards and an open popup receive updates; the 5-second refresh stays active while the main session works or subagents are running. The costs shown are those recorded by Pi, not local estimates: a provider or model without pricing may keep reporting zero.

Check from source:

```bash
pnpm --filter @piframe/agentd exec tsc --outDir .temp/bugfix-tests
node --test apps/agentd/.temp/bugfix-tests/test/sessionCostPersistence.test.js
cd apps/pi_frame
flutter test test/subagent_cost_updates_test.dart test/subagents_feature_test.dart test/cost_breakdown_models_test.dart
```

The TypeScript build uses a temporary folder: it does not change the daemon bundle or the Windows release in use.

---

## Unauthorized Copilot models, or context tier ignored

**Causes fixed:** the picker filtered only the local `enabledModels`, without checking GitHub policies. The context limit was kept in PiFrame but not applied to Pi; the duplicated checks in the GUI and in the daemon used a fixed 80% threshold and could ignore errors.

**Current behavior:** the daemon checks Copilot entitlements and refuses to select an unauthorized model. Workspace exposes a custom maximum and a percentage margin; the worker applies the threshold to Pi's native compaction. Errors while applying it are no longer accepted as success.

- If the context chip in the chat shows a tier but opens nothing, use the updated build: the composer could keep an empty catalog loaded before the daemon connection. It now reloads the models on click and reports missing data explicitly. The chat and Workspace use the same picker.
- The maximum slider is hidden until you choose **Custom** in Context size. Exact tiers (for example 272k) stay selectable; Custom uses steps of 50k. The margin uses steps of 0.5%, from 0.5% to 25%.
- If a Copilot model is missing, check your account and its entitlement in your organization. If a verification notice appears, check the network and authentication with Pi; PiFrame does not fall back to the full static catalog. The cache of successful checks lasts at most one minute.
- If **Pi did not apply the context limit** appears, update Pi and restart the worker. The check needs `getSettings` in the extension API; the real-runtime test uses Pi 1.4.0.
- 5% means compacting at **95%** of the chosen maximum. The default 2.5% gives 200k a threshold of 195k.
- If compaction does not start, check that Pi's automatic compaction is on. Change the limit and margin while no turn is running.
- If compaction fails or does not reduce the context enough, raise the limit or reduce the context Pi keeps in its settings. A preventive limit cannot guarantee a billing cap: single outputs and summary requests use tokens.

Repeatable check from source, with no calls to paid providers: build the daemon and run `node tools/scripts/smoke-context-policy.mjs`. The test uses real Pi with a local HTTP model and isolated temporary directories.

---

## 1. Windows: blank or white window at startup

### Symptoms
When the desktop app starts on Windows:
- The PiFrame window opens (with or without a frame), the process is alive in Task Manager and uses a normal amount of memory.
- The rendering area (client area) stays **completely white** or **completely black**.
- The app does not hang and logs no Dart exceptions in the system logs or the debug console (`flutter run`).
- **Same behavior with a fresh app**: a clean Flutter app generated with `flutter create` shows exactly the same white rendering.

### Root cause
On Windows, Flutter relies on the **ANGLE (Almost Native Graphics Layer Engine)** backend on Direct3D 11 (`EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE`) and on the **Impeller / Skia** engine.

With:
1. **Virtual display drivers or secondary USB screens**:
   - `USB Mobile Monitor Virtual Display` (`ROOT\DISPLAY\0000`)
   - `IddSampleDriver`
   - Spacedesk, Duet Display, DisplayLink or RDP/VNC virtual monitors
2. **Hybrid multi-GPU setups** (for example an integrated AMD Radeon/Intel GPU plus a dedicated NVIDIA GeForce RTX GPU)
3. **A corrupted Desktop Window Manager (DWM) state** after a sudden shutdown, a system crash (for example Kernel-Power event 41) or a resume from sleep/hibernation that lost the DirectX context

the Windows Desktop Window Manager does not finish presenting the DirectX swapchain (`SwapChain11::present` or `EGLSurface`) to the `FLUTTERVIEW` child window, so the initial system background (solid white or transparent black) stays on screen even though the widget tree and Flutter's rasterizer work normally.

*Official Flutter issues*:
- [flutter/flutter#149709: Flutter windows desktop screen comes up blank with 2 monitors connected to laptop](https://github.com/flutter/flutter/issues/149709)
- [flutter/flutter#160948: Impeller GPU calls fail to render on Windows (GLES)](https://github.com/flutter/flutter/issues/160948)
- [flutter/flutter#137321: Launching the app from a non-main monitor shows a white screen on Windows](https://github.com/flutter/flutter/issues/137321)

---

### Workarounds and fixes

#### Fix 1: clean system restart
If the problem appears after a crash, a driver update or standby:
1. Restart Windows fully (**Start menu → Restart**, avoiding Fast Startup).
2. After the restart, the DirectX / DWM subsystem recreates the EGL/ANGLE contexts cleanly and the interface starts normally.

#### Fix 2: disable or disconnect virtual or secondary displays
If the problem persists after a restart:
1. Open **Device Manager** (`devmgmt.msc`).
2. Expand **Display adapters**.
3. If a virtual device is present (for example `USB Mobile Monitor Virtual Display`, `IddSampleDriver` or similar):
   - Right-click it and choose **Disable device** (or disconnect the phone mirroring app).
4. Start PiFrame again.

#### Special case: no active monitor (monitor off or DisplayPort in deep sleep)
If the monitor is turned off, or a DisplayPort monitor enters deep sleep, Windows can be left without an active display (Device Manager shows the monitors as *Unknown*, and only generic 60 Hz modes remain). In this state PiFrame opens with a white window even with Flutter's software rendering, because the engine gets no vsync from the display. Other apps (terminal, Electron) may look normal.
1. Turn the monitor on or wake it, then restart PiFrame.
2. For unattended sessions (for example automated recordings), turn off monitor standby (`powercfg /change monitor-timeout-ac 0`) and the monitor's deep sleep feature.

#### Fix 3: assign the dedicated GPU (Windows graphics settings)
On systems with integrated graphics and a dedicated graphics card (for example AMD + NVIDIA):
1. Open **Windows Settings → System → Display → Graphics**.
2. Add the `PiFrame.exe` executable (by default in `%LOCALAPPDATA%\Programs\PiFrame\`, the per-user install directory).
3. Click **Options** and choose **High performance** (NVIDIA GeForce RTX) to force the primary D3D11 adapter instead of the software or integrated fallback.

---

## 2. Remote connection: fallback page "The local daemon is running"

### Symptoms
After scanning the QR code with a phone or opening the Tailscale / Cloudflare URL:
- The phone shows a page with a static box titled *"PiFrame Daemon"* and the text *"The local daemon is up and running on loopback"*, and the interactive PiFrame interface does not load.

### Cause
The `pi-agentd` daemon could not find the built Flutter web app directory (`apps/pi_frame/build/web`), so it served the static emergency courtesy page.

### Fix
1. The daemon's search paths now include `apps/pi_frame/build/web`, `~/.piframe/web/` and the `web/` folder next to the executable.
2. The built web app is synced to `~/.piframe/web/` and included in the release installers.
3. If you run from source, build the web version with:
   ```bash
   cd apps/pi_frame
   flutter build web --no-web-resources-cdn
   ```
   and copy the generated files to `~/.piframe/web/`.

## 3. Web app: the integrated browser inside the browser

### Use case
In the web version of PiFrame viewed from a phone or a remote browser, the *integrated Web Browser* button and pane were removed on purpose:
- On remote devices (for example iPhone, Android, an external browser), opening a browser inside an embedded webview is redundant, and WebView2 is a native Windows desktop technology.
- Remote web mode exposes only the relevant work areas: **Chat**, **File Explorer** and **Git Changes**.

---

## 4. Daemon unreachable or connection error with a source build

### Symptoms
When starting a `PiFrame.exe` built by hand from source (for example from `apps/pi_frame/build/windows/x64/runner/Release/PiFrame.exe`):
- The app starts, but the sessions list shows `TimeoutException after 0:00:08.000000`.
- The Release bundle contains `scanFastSnapshot` but not `getCachedSnapshot`.

### Cause
A manual Flutter build (`flutter build windows`) does not rebuild the daemon. The old `session.list` waited for the file-system scan before answering; the first updated bundle added the fast index, but still waited for its whole scan. That bundle contains `scanFastSnapshot` but not `getCachedSnapshot`, so it can still exceed the UI's 8-second limit.

### Fix
1. From the monorepo root, rebuild the daemon before the app:
   ```powershell
   pnpm build:agentd
   ```
   The Windows build now refuses the sidecar if it is missing or does not contain both `scanFastSnapshot` and `getCachedSnapshot`.
2. Rebuild Flutter. CMake copies the updated bundle next to `PiFrame.exe`. Copy `node.exe` into the same directory if it is not there yet.
3. If the daemon is already running, wait for active work to finish and use **Settings → Restart daemon**. Rebuilding the app neither rebuilds nor stops a daemon that is already running.

The new daemon answers from the in-memory/cached snapshot and updates the index in the background; with a cold cache it waits for the fast scan for at most 250 ms, then continues in the background. The check neither reads nor rewrites Pi sessions. If the error remains after these steps, check that the `pi-agentd.cjs` next to `PiFrame.exe` contains `getCachedSnapshot`; a Flutter rebuild alone does not update `apps/agentd/dist/pi-agentd.cjs`.

---

## 5. Installing dependencies: `EBUSY: resource busy or locked, symlink` (Windows)

### Symptoms
Running `pnpm install` or `pnpm build:all` on Windows fails with:
```text
EBUSY: resource busy or locked, symlink ...
'tsc' is not recognized as an internal or external command
```

### Cause
A running process (a `PiFrame.exe` instance, the `pi-agentd` daemon or a terminal) holds a lock on the monorepo package folders while `pnpm` tries to create symbolic links. The dependency installation stops before it links the TypeScript compiler (`tsc`).

### Fix
1. Stop any app or daemon instances:
   ```powershell
   Stop-Process -Name "pi-agentd","pi-frame","PiFrame" -ErrorAction SilentlyContinue
   ```
2. Run the dependency installation and the build again:
   ```powershell
   pnpm install
   pnpm build:all
   ```

---

## 6. CI/Release: Flutter tests, GitHub Pages or the Windows bundle

### Duplicate user message in the chat

The interface shows a sent message at once. When the daemon gets the confirmation from Pi, it reconciles the event with the optimistic entry instead of adding a second row. If sending fails, the bubble keeps its text and attachments: use **Retry**, or double-click the bubble to edit it in the composer. To check this logic, run:

```bash
cd apps/pi_frame && flutter test test/session_reducer_test.dart test/failed_message_flow_test.dart
```

### Flutter tests failing in CI

The test `resolvePathForOsExplorer correctly resolves WSL and Windows paths` covers the Windows/WSL output, which is produced only when `Platform.isWindows` is true. Linux uses POSIX resolution: the Windows test is skipped there and a separate POSIX test checks that behavior. If the test fails, run the targeted test first, then the same Flutter suite and analysis that CI uses:

```bash
cd apps/pi_frame && flutter test test/transcript_rich_test.dart
```

From the repository root, run the wrappers for all Flutter tests and the Flutter analysis:

```bash
node tools/scripts/test-flutter.js
node tools/scripts/lint-flutter.js
```

### GitHub Pages returns 404

In **Repository Settings → Pages**, set **Build and deployment → Source** to **GitHub Actions**. If the Pages setup fails, the job now reports the failure instead of hiding it; check that step and the repository permissions.

### The Windows release reports a missing executable

CMake produces `PiFrame.exe` and the installer uses the same name. The bundle check in the Release workflow must look for `PiFrame.exe` (not `pi_frame.exe`). Check this locally with:

```bash
node --test tools/scripts/test-windows-release-name.test.mjs
```

### The Linux build fails because WebKitGTK is missing

If CMake reports `None of the required 'webkit2gtk-4.1;webkit2gtk-4.2;webkit2gtk-4.3' found`, the development library required by the `webview_win_floating` plugin is missing. On Ubuntu 24.04 install:

```bash
sudo apt-get install libwebkit2gtk-4.1-dev
```

The Release workflow installs this package in both the validation and the Linux build. The `.deb` also declares `libwebkit2gtk-4.1-0` as a runtime dependency: install it with `sudo apt install ./PiFrame-<version>-linux-amd64.deb` so the dependencies are resolved.

Check the declarations from the repository root:

```bash
node --test tools/scripts/test-windows-release-name.test.mjs
```

To ship the correct runtime dependency too, create a new release that includes this fix. **Actions → Release → Run workflow** from `main` with an older tag (for example `v1.1.0`) uses the build dependencies of the updated workflow, but the packaging script stays the one of the old tag: a `.deb` rebuilt that way does not include the new runtime declaration. Rerunning the old run only still uses the workflow without the fix.

### The Linux build fails because libnotify is missing

Flutter's notifier plugin for Linux needs `pkg-config` to find `libnotify`. Install the development package before building:

```bash
sudo apt-get install libnotify-dev
```

Installed Debian packages also need the runtime dependency `libnotify4`. The release CI installs `libnotify-dev` for validation and the Linux build; the `.deb` package declares `libnotify4`.

---

## 7. Constant WebSocket disconnects (code 4009) and snapshots piling up in the journal

### Symptoms
- PiFrame keeps disconnecting and reconnecting forever ("Client too slow / backpressure buffer exceeded 128MB", close code `4009`) when it opens or starts with very large pinned sessions (for example > 100 MB).
- Disk use in the journal folder (`~/.piframe/journal/<sessionId>/`) grows steadily to tens of gigabytes (for example 30 GB with hundreds of `snapshot.<seq>.json` files).

### Root causes
1. **Unbounded transcript in the snapshot**: when a session was attached, `SnapshotBuilder.build()` serialized the whole message history into the WebSocket snapshot payload. For sessions with thousands of messages and large tool outputs (for example 130–145 MB), the frame exceeded the 128 MB backpressure safety threshold in `connection.ts`, and the connection closed with code 4009. Because pinned sessions are reattached automatically at startup, the app entered an endless reconnect loop.
2. **No retention policy for daemon snapshots**: `EventJournal` writes a snapshot checkpoint every 500 events, so a resume does not need to reread the whole event log. `Spill.ts` serialized snapshots with full indentation (`null, 2`) and had no rotation or cleanup of old files, even though loading (`loadLatestSnapshot()`) reads only the most recent snapshot file.

### Fix
1. **Bounded snapshot window (`SnapshotBuilder.ts`)**:
   - `SnapshotBuilder` limits the messages in the initial snapshot frame to the 100 most recent (`MAX_SNAPSHOT_ENTRIES = 100`).
   - Unusually large text fields (for example huge file dumps in tools) have a safety cap (`MAX_ENTRY_TEXT_BYTES = 256 KB`), which shrinks the payload from over 130 MB to about 1.6 MB and removes any risk of WebSocket congestion or UI freezes.
2. **Automatic cleanup and retention (`Spill.ts`)**:
   - Snapshots are written as compact JSON without needless indentation.
   - `pruneOldSnapshots(retainCount = 2)` keeps only the two most recent snapshots. It runs at every new checkpoint and when the journal initializes (`init`), deleting every orphaned checkpoint and freeing the disk space.

---

## 8. Jerky or jumping scrollbar when loading older messages

### Symptoms
- After clicking "Load earlier messages", the scrollbar thumb moved jerkily and wrongly, jumping up and down even though the user kept scrolling smoothly in one direction.
- The button loaded a small number of messages (35 at a time), so long transcripts needed many clicks.

### Root causes
1. **Unstable dynamic extent estimate (`estimateMaxScrollOffset`)**: Flutter computes `maxScrollExtent` for `ListView.builder` by estimating the total height from the average of the items currently on screen. In a chat/log interface where a short message takes 40 px and a code block or tool diff takes 800 px, the estimated total height changed sharply (for example from 10,000 px to over 100,000 px) between scroll frames, so the thumb position bounced.
2. **Arbitrary post-load jump (`jumpTo(oldOffset + diff)`)**: when older messages were loaded at the top of the list, the app tried a jump proportional to a `maxScrollExtent` difference that had no real layout behind it, sending the position to invalid or out-of-scale offsets.
3. **Full widget-tree rebuilds while scrolling**: the scroll notification listener called `setState` on `_userScrolledUp` on every scroll update, invalidating the whole transcript view during a drag.
4. **Double increment of `_visibleCount`**: both the button callback and the `build()` cycle increased the visibility counter when the new messages were inserted.

### Fix
1. **Load 250 messages at a time (~7x)**:
   - In `Dispatcher.ts`, the maximum for `session.getHistory` was raised to 1000 items, with a default of 250.
   - In the frontend (`daemon_providers.dart` and `transcript_view.dart`), the button loads 250 messages per click, while the initial open keeps a fast set of 35 messages.
2. **`SmartTranscriptChildDelegate` and a per-ID height cache**:
   - A custom delegate keeps a persistent cache of measured widget sizes (`_MeasureSize`), keyed by stable message ID.
   - The scroll estimate (`estimateMaxScrollOffset`) uses the sum of items already measured plus a stable historical average for those still outside the viewport, so the scrollbar progresses monotonically, without oscillation.
3. **Anchoring and keeping the reading position**:
   - On 'Load earlier messages', the app tracks the screen position of the first visible message through `_anchorKey` and computes the height of the messages inserted above.
   - It compensates the offset by the added height, with sub-pixel refinement in a post-frame callback: the message the user was reading stays exactly where it was on screen, instead of jumping to the start of the history. Older messages stay reachable by scrolling up.
   - The widget cache extent was raised to 2000 px (`ScrollCacheExtent.pixels(2000.0)`) to avoid constantly destroying and recreating large items.
4. **A `ValueNotifier<bool>` for the floating button**:
   - The scroll-to-bottom button appears and disappears through a `ValueListenableBuilder`, so scrolling never triggers a global `setState` of the whole view.

---

## 9. Several model menus, wrong "Not delivered" message, agent question stuck

### Symptoms
- Clicking the model picker several times before its menu appeared opened several popups.
- The first message after reopening a session was marked "Send failed" even though Pi had received it and the agent answered (only later).
- A multiple-choice question from the agent (the card above the composer) did not let you press "Send" or interact, blocking the chat.

### Root causes and fixes
1. **Model/thinking picker**: the catalog loaded asynchronously before `showMenu`, so every tap launched a new menu. `composer.dart` now ignores taps while a picker is opening or open (`_guardPicker`), and loading has a 10 s timeout, so the picker never stays stuck.
2. **False-negative delivery**: Pi acknowledges `prompt` only after its preflight (for example a pre-prompt compaction of a large session, or extension hooks), which can exceed the daemon's 30 s. `StdioPiTransport` now treats a slowly acknowledged `prompt` as accepted (`disposition: pending`); a late refusal from Pi arrives as `worker.diagnostic`. Other commands keep the timeout with an error.
3. **Stuck question card** (`extension_ui_dialog.dart` + `composer.dart`):
   - the body (message and options) scrolls with a maximum height: the Cancel/Send buttons stay visible even with many options or long text;
   - the buttons no longer depend on the claim result: only "already in use by another client" blocks the card; a slow, failed or offline claim does not disable it (the daemon arbitrates the answer anyway);
   - after an answer, a timeout, or when the request no longer exists on the daemon (`Request not found`), the card closes locally, without waiting for the `ui.resolved` event.
4. **Models with the same name on different providers**: the session kept only the display name, and the picker could highlight several rows or resolve the entry to the first provider. PiFrame now keeps both provider and ID; menus and lookups use both, the session menu tells providers apart, and `/model` asks for `provider/id` when the name is ambiguous.

---

## 10. Chat jitter when expanding activity/subagent cards, and cards reopening on session switch

### Symptoms
- Expanding or minimizing the activity and subagent cards made the chat list visibly "shake" and move up and down.
- When a session opened or you switched session, the activity or subagent card reopened expanded, taking half the height of the chat pane.

### Root causes
1. **Correction loop in the bottom-anchored controller (`_BottomAnchoredScrollPosition`)**: during the viewport resize animation (`AnimatedSize`), the controller saw `maxScrollExtent` change and called `correctBy` on every frame. That invalidated the layout and fired a `ScrollUpdateNotification`, which was wrongly read as a manual user scroll, toggling `_userScrolledUp` back and forth and making the anchor point oscillate.
2. **Two nested `AnimatedSize` widgets**: both `TranscriptView` and the inner `TodoPopDown` and `SubagentsPopDown` widgets applied their own `AnimatedSize`, producing out-of-phase animations and measurement conflicts.
3. **Counters starting at zero on session switch or open**: `_lastActiveTodoCount` and `_lastRunningSubagentCount` started at zero for every session, so existing tasks or subagents were read as a new increase and triggered auto-expansion (`_activeBookTab = _ActiveBookTab.todos` or `subagents`). `_activeBookTab` was also not reset to `none` when switching sessions (`didUpdateWidget`).

### Fix
1. **Stable layout, no scroll-notification loop**:
   - The nested `AnimatedSize` is gone: when `hideBookTab: true` (handled directly by the transcript view), `TodoPopDown` and `SubagentsPopDown` no longer nest a second `AnimatedSize`, which removes the measurement conflict and the out-of-phase calculations.
   - The spurious handling of `scrollDelta` without `dragDetails` in `_handleScrollNotification` was removed; `_userScrolledUp` now changes only on real user gestures (`UserScrollNotification` or an active drag with drag details).
   - `_toggleBookTab` marks the animated card transition (250 ms) as programmatic (`_isProgrammaticScroll = true`), so it produces no spurious scroll notifications.
2. **Minimized by default on session open and switch**:
   - The active session ID is tracked (`_trackedSessionId`); on the first open or a session switch (`didUpdateWidget`), `_activeBookTab` defaults to `_ActiveBookTab.none`.
   - The active task and subagent counters are synced with the session's current values on load without triggering auto-expansion, so the cards stay minimized and the whole chat stays visible, with the compact pills in the top bar.

---

## 11. Building the Windows installer: `node.exe` or `PiFrame.exe` locked (`IOException` / file in use)

### Symptoms
During the step `[4/4] Staging runtime assets & compiling Inno Setup installer...` of `pnpm run package:windows` (or `package-windows-installer.ps1`), the run stops with:
```text
Copy-Item : The process cannot access the file '...\apps\pi_frame\build\windows\x64\runner\Release\node.exe' because it is being used by another process.
In ...\tools\scripts\package-windows-installer.ps1
+ Copy-Item $nodePath (Join-Path $bundle 'node.exe') -Force
    + CategoryInfo          : NotSpecified: (:) [Copy-Item], IOException
    + FullyQualifiedErrorId : System.IO.IOException,Microsoft.PowerShell.Commands.CopyItemCommand
```

### Root cause
If `PiFrame.exe` was started earlier from the release folder or during local tests, the app starts the `pi-agentd` daemon in the background with the `node.exe` in `apps/pi_frame/build/windows/x64/runner/Release/`.
On Windows, the kernel blocks writing or overwriting any `.exe` file tied to a running process. If the `node.exe` daemon or the `PiFrame.exe` app stays alive in the background, `Copy-Item` cannot overwrite the file. Local sessions with WebView2 also created tens of megabytes of temporary cache in the `PiFrame.exe.WebView2` folder, which was wrongly included in the Inno Setup archive.

### Fix
1. **Automatic termination of stale processes**: [`tools/scripts/package-windows-installer.ps1`](../tools/scripts/package-windows-installer.ps1) finds and stops running `node` or `PiFrame` processes inside the release directory (`$bundle`) when staging starts.
2. **Retry, and tolerance for identical files**: a progressive retry was added; if `node.exe` has the same size as the system executable, the build continues with a warning instead of stopping.
3. **WebView2 cache cleanup and exclusion**: `package-windows-installer.ps1` removes `PiFrame.exe.WebView2` before packaging, and [`packaging/windows/PiFrame.iss`](../packaging/windows/PiFrame.iss) explicitly excludes the temporary folder (`Excludes: "*.WebView2\*,*.WebView2"`), which makes the final executable much smaller.
4. **Quick repackaging**: if the Flutter build already succeeded, you can create the installer at once without rebuilding Flutter:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/scripts/package-windows-installer.ps1 -SkipBuild
   ```

---

## 12. Windows: "MSVCP140.dll was not found" at startup on clean installs

### Symptoms
On a new or clean Windows 10 or Windows 11 install (or inside a clean virtual machine), the app does not start and the system shows:
```text
The code execution cannot proceed because MSVCP140.dll was not found. Reinstalling the program may fix this problem.
```
Sometimes with similar errors for `VCRUNTIME140.dll` or `VCRUNTIME140_1.dll`.

### Root cause
Flutter desktop apps for Windows and their C++ plugins are built with MSVC (Microsoft Visual Studio C++) and link the C/C++ standard library dynamically (`msvcp140.dll` and `vcruntime140.dll`).
On clean Windows installs (unlike developer machines with Visual Studio), the **Microsoft Visual C++ 2015–2022 Redistributable (x64)** is not preinstalled.

### Fix
1. **Immediate fix on the target machine / VM**:
   Install the official Microsoft Visual C++ 2015-2022 (x64) runtime:
   - With `winget`:
     ```powershell
     winget install Microsoft.VCRedist.2015+.x64
     ```
   - Or download Microsoft's official executable:
     [https://aka.ms/vs/17/release/vc_redist.x64.exe](https://aka.ms/vs/17/release/vc_redist.x64.exe)
2. **Fix built into the package (app-local deployment)**:
   [`tools/scripts/package-windows-installer.ps1`](../tools/scripts/package-windows-installer.ps1) now includes the CRT runtime DLLs (`msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll` and so on) in the release directory next to `PiFrame.exe`. The resulting installer is fully self-contained and works at once, also offline and on completely fresh Windows systems, without external installs.

---

## 13. Premature "Answer completed" system notifications while the agent is still working

### Symptoms
- While the app is not focused, the operating system shows an "Answer completed" desktop notification, but clicking it shows that the agent is still running (running intermediate tools, waiting for background subagents, compacting the context or retrying a network call).

### Root causes
1. **Settlement check too permissive**: `SessionNotificationWatcher` treated any transition with `agentStatus != AgentStatus.working` as "finished". Intermediate states `AgentStatus.retrying`, `AgentStatus.compacting` or `AgentStatus.awaitingUser` (a user dialog request) therefore triggered the answer-completed notification.
2. **Subagents and follow-up queues ignored**: if the agent started background subagents, or messages were waiting in the steering/follow-up queue, the end of the parent turn was mistaken for the end of all the work.
3. **Existing entries not pre-seeded when the watcher attached**: when the watcher mounted on existing sessions, entries created before observation started could cause spurious notifications on later state updates.

### Fix
1. **Deterministic full-settlement check**: in `SessionNotificationWatcher`, "Answer completed" is sent only if the agent was really active (`_isRunActive`) and is now in a terminal state (`AgentStatus.settled` or `AgentStatus.idle`), with no streaming, no running tool call, no pending interactive dialog request and empty steering/follow-up queues.
2. **Subagent lifecycle tracking**: `SessionNotificationWatcher` listens to `subagentsFamily` and holds back the completion notification while linked subagents are still running (`isRunning == true`). When the last subagent finishes, the notification is sent.
3. **Pre-seeding of existing messages at init**: in `initState`, every assistant message and UI request already in the session is recorded in `_handledEntryIds` and `_handledUiRequestIds`, so only new output produced during the current run can raise alerts.

---

## 14. Pinned sessions reordering unexpectedly, and drag-and-drop support

### Symptoms
- When an answer arrived in any pinned session, the session moved inside the "Pinned" box, jumping to the top or moving by the time of its last answer.
- The user could not move or reorder pinned sessions by pressing and dragging them with the mouse.

### Root causes
1. **Order inherited from `allSessions`**: pinned sessions were taken with `allSessions.where((s) => pinnedIds.contains(id))`. Because the daemon sorts `allSessions` by descending activity (`updatedAt`), every new answer moved the session to the top, changing the order the user had chosen.
2. **Unindexed state and a static view**: `pinnedSessionsProvider` stored a `Set<String>` with no positional reordering API, and the sidebar rendered the list as flat items in a `ListView.builder` without drag-and-drop gestures.

### Fix
1. **Stable, persisted order**: `PinnedSessionsNotifier` manages an ordered `List<String>` saved on disk in `pinned_sessions.json`. The sidebar now builds `pinnedSessions` in the exact order of `pinnedIds`, so positions are fully stable whatever the agent does.
2. **Reordering with a long press and drag (mouse drag-and-drop)**: the pinned section lives in a `CustomScrollView` with `SliverReorderableList` and `ReorderableDelayedDragStartListener`:
   - A short mouse click opens and selects the session as usual.
   - Pressing and holding lets the user grab a pinned session and drag it up or down to any position.
   - The new order is saved to disk at once and kept.

---

## 15. Cannot connect to or restart the daemon after a Windows Release build (bundle not synced, stale version)

### Symptoms
- After building PiFrame for Windows (for example `flutter build windows --release`), the app cannot connect to the local daemon.
- The status banner shows a connection error, and «Restart daemon» keeps failing without ever connecting.

### Root causes
1. **Version mismatch of the sidecar bundle (`pi-agentd.cjs`)**:
   - `PiFrame.exe` is built with the current app version (for example `v1.3.0`).
   - If the Windows runner output folder (`apps/pi_frame/build/windows/x64/runner/Release`) holds an older daemon bundle (`pi-agentd.cjs`, for example `v1.2.0`), `_spawnSidecarDaemon()` starts the file found next to the executable.
   - At startup, the version check in `_probeActiveDaemon()` sees `runningSemVer < appSemVer` (1.2.0 < 1.3.0). To prevent protocol incompatibilities, the client kills the daemon process at once (`Process.killPid(pid)`) and deletes `daemon.json` and `daemon.token`.
   - The client then tries to autospawn again, starts the old bundle again, and kills it again: an endless failure loop.
2. **CMake POST_BUILD did not update the bundle**:
   - `CMakeLists.txt` had an `install(FILES "${AGENTD_BUNDLE}" ...)` rule. The `install` step is not run by the normal Flutter / MSBuild build commands without the `INSTALL` target, so a stale `pi-agentd.cjs` stayed in the `Release` directory.
3. **Blind spots in `restartDaemon`**:
   - `restartDaemon()` looked for the PID to kill only in `daemon.json`. If `_probeActiveDaemon()` had already deleted `daemon.json` after the version mismatch, `restartDaemon()` did not find the process (it did not check `daemon.pid` or `daemon.lock`) and did not clean up leftover lock files.
   - The 300 ms wait was also too short on Windows for the operating system to release the PID and the lock before the new start.

### Fix
1. **Automatic daemon sync in CMake POST_BUILD**:
   - [`apps/pi_frame/windows/runner/CMakeLists.txt`](../apps/pi_frame/windows/runner/CMakeLists.txt) has a `POST_BUILD` command on `${BINARY_NAME}` with `${CMAKE_COMMAND} -E copy_if_different`, which always copies the updated `${AGENTD_BUNDLE}` into the executable folder (`Release` / `Debug`).
2. **Robust PID lookup and lock cleanup in `restartDaemon`**:
   - In [`apps/pi_frame/lib/data/daemon/daemon_locator.dart`](../apps/pi_frame/lib/data/daemon/daemon_locator.dart), `restartDaemon()` checks `daemon.json`, `daemon.pid` and `daemon.lock` in turn to find any orphaned or still-running daemon process.
   - It removes every runtime file (`daemon.json`, `daemon.token`, `daemon.pid`, `daemon.lock`) and waits long enough (600 ms) for Windows to release socket and file handles before the respawn.
3. **More fallback paths in `devPaths`**:
   - `devPaths` now also includes paths relative to the repository root starting from `exeDir` (`build/windows/x64/runner/Release`), so the app finds the freshly built bundle in `apps/agentd/dist/pi-agentd.cjs`.

---

## 16. Orphaned GPU processes (`typeperf.exe`, `nvidia-smi.exe`) or sampling timers left running after a disconnect (technical stats)

### Symptoms
- After turning on technical stats (then called *Nerd stats*) and later closing the app or turning the option off, background processes such as `typeperf.exe` or `nvidia-smi.exe` stayed in the Windows process list / Task Manager.
- During test runs, or after a fast client exit, the daemon kept polling the counters with zero subscribers.

### Root causes
1. **Child process respawned by mistake on exit code 1 during `stop()`**:
   - In `WindowsTypeperfGpuProvider`, `stop()` called `child.kill()`. On Windows, a killed `typeperf` usually exits with code `1`. The `exit` handler read the non-zero code as an unexpected error and called `handleFailure()`, which started a new, orphaned `typeperf` process.
2. **Race condition and orphaned timer in `SystemMetricsService.startSampling()`**:
   - The asynchronous `getProvider()` initialization could finish after the client had already unsubscribed or during `stop()`. Without a concurrency check, the daemon started the GPU provider and the interval timer (`setInterval`) and left them running forever with zero subscribers.

### Fix
1. **A deterministic `stopped` flag and event decoupling in every GPU provider**:
   - `WindowsTypeperfGpuProvider`, `NvidiaGpuProvider` and `MacIoregGpuProvider` have a `stopped` flag and check that each event comes from the active `this.child`. After `stop()`, any late event (`stdout`, `error`, `exit`) is ignored, without a respawn and without changing the sample state.
   - Every provider accepts injected spawn/exec functions in tests, so the suites are fully isolated and create no real processes.
2. **A single in-flight `startPromise`, and subscribers checked again**:
   - `SystemMetricsService.startSampling()` uses one in-flight promise for concurrent subscriptions. When `getProvider()` resolves, it checks `subscribers.size > 0` and the `stopped` state again before starting the GPU provider and creating the interval timer.

---

## 17. Subagents fail to start after removing PiFrame / ERR_MODULE_NOT_FOUND subagent-context-limit.mjs

### Symptoms
- After removing or uninstalling PiFrame (or deleting the `~/.piframe` folder), starting subagents from the official Pi CLI or other interfaces fails with:
  `Error [ERR_MODULE_NOT_FOUND]: Cannot find module '.../.piframe/runtime/subagent-context-limit.mjs'`

### Root cause
In Pi's user settings (`~/.pi/agent/settings.json`), `subagents.agentOverrides.<name>.subagentOnlyExtensions` holds the path of the context-limit extension generated by PiFrame (`subagent-context-limit.mjs`). If the `~/.piframe` directory is deleted, Node.js can no longer find the `.mjs` file when the subagent starts.

### Fix
1. **Before uninstalling PiFrame**: reset the context limits set for subagents in PiFrame's *Agents* tab (Settings → Agents) and click *Save changes*. PiFrame removes the extension path from the `subagentOnlyExtensions` array in `settings.json`.
2. **If PiFrame is already uninstalled**: open `~/.pi/agent/settings.json` in a text editor and remove the reference to `subagent-context-limit.mjs` from `subagents.agentOverrides.<name>.subagentOnlyExtensions` for each configured agent (or remove the `subagentOnlyExtensions` property if it holds no other extensions).
3. **Automatic regeneration with PiFrame**: if you reinstall PiFrame or start its daemon (`agentd`) again, the daemon reads `settings.json` at startup (read-only): if it finds active references to the extension in `subagentOnlyExtensions`, it regenerates `~/.piframe/runtime/subagent-context-limit.mjs` when it is missing or out of date.

---

## 18. Technical stats stuck on `n/a` after turning them off and on again

### Symptoms
- With technical stats on, the values show correctly. After turning the option off and on again (or after closing and reopening the app several times without restarting the daemon), CPU, RAM, disk and GPU stay on `n/a`.
- `system.metrics.subscribe` answers `completed`, but the daemon no longer sends `system.metrics` events. Restarting the daemon fixes it for a while.

### Cause
- In `SystemMetricsService.startSampling()` the start promise was cleared in a `finally` block inside the async function. When the GPU provider already existed (from the second subscription on), the function hit no `await` and ran synchronously: the `finally` cleared `startPromise` *before* the assignment, which then stored an already-resolved promise that was never cleared. On the next subscription `startSampling()` returned that promise without restarting the timer and the provider.

### Fix
- The start promise is assigned first and cleared by an outer `finally` only if it is still the current one. A regression test runs five consecutive subscribe/unsubscribe cycles and checks that every cycle restarts sampling.
- This needs an updated daemon: after updating, restart the daemon (Settings → Daemon) to load the fix.

---

## 19. Web app on the phone: blank background after an update, offset taps, slowness

### Symptoms
- After updating PiFrame or the daemon, the web app on an already paired phone shows only the blank background until you pair again.
- Loading on iPhone is very slow.
- Taps register about 1 cm below the point touched.
- The interface stutters while answers stream.

### Causes
- Flutter's service worker served a stale version of the app from its cache, incompatible with the new daemon; the pairing cookie was a session cookie, and if the tunnel did not start at boot the daemon did not retry.
- Web files were not compressed, and the daemon ran synchronous commands (`tailscale status`) on every state update.
- Leftover scroll/zoom of the iOS visual viewport (URL bar, keyboard, pinch) shifted the tap coordinates.
- The animated glowing border with blur and the animated intro were too heavy for the mobile browser canvas.

### Fix
Update PiFrame (app and daemon): all the fixes are included (see [install.md section 22](install.md#22-mobile-web-app-reliable-startup-aligned-taps-and-better-speed)). If you still see a message:
- **"Pair the device again"**: generate a new QR code from Settings → Remote connection.
- **Screenshots or files from the phone do not reach the agent**: the device needs `control` mode (Settings → Remote connection) and an updated daemon. In `view` mode a notice says the device is read-only. The limit is 50 MB per file.
- **Interface zoomed or cut off while typing, composer buttons gone**: this was iOS auto-zoom on focusing a field with text under 16 px, combined with a composer taller than the space above the keyboard. Update the web app and reload it (close and reopen the Home Screen icon).
- **"Computer not reachable"**: check that PiFrame is open, remote connection is on and Tailscale is connected on the phone. Note: a web app added to the iOS Home Screen has storage separate from Safari, so it must be paired from there too.

## Integrated terminal: "staircase" output with `git`

### Symptoms
In the integrated terminal, the output of commands such as `git branch`, `git log --oneline` or `npm test` appeared shifted: each line started at the column where the previous one ended.

### Cause
The integrated terminal starts the shell through pipes, without a pseudo-console. Native programs such as `git` write lines that end with LF only, and the emulator did not return to the start of the line.

### Fix
PiFrame now converts every lone LF to CRLF before writing to the terminal (stdout and stderr), also when a CRLF arrives split across two chunks. Update PiFrame to get the fix.

## WSL sessions: "Send failed: spawn ...\node.exe ENOENT" after inactivity

### Symptoms
After a period of inactivity (worker stopped after 30 minutes, PC in standby), sending in a session whose folder is `\\wsl.localhost\...` failed with `spawn C:\...\node.exe ENOENT`, even though `node.exe` exists. Restarting the daemon from Settings did not help.

### Cause
The `\\wsl.localhost\<distro>\...` folder is served by the WSL VM. When the VM is stopped and the redirector does not restart it, Windows cannot open the new process's working folder, and Node reports the error with the executable's name instead of the folder's.

### Fix
Before starting a worker in a WSL folder that cannot be reached, the daemon starts the distro with `wsl.exe -d <distro> --exec true` and then spawns. If the spawn still fails, the error names the folder (`(cwd: ...)`). Update PiFrame to get the fix.

## Steer refused during compaction, and context limit inherited from the previous model

### Symptoms
- During "Compacting…", a message sent with Enter failed with `Agent is streaming. Specify streamingBehavior`.
- After switching model (for example from Haiku to Opus), the previous model's context limit stayed and the session kept compacting.

### Fix
- During compaction the composer sends the message as a steer. The daemon passes steers and follow-ups to Pi through `prompt` with `streamingBehavior`: Pi queues it if it is running, or starts a run if it has already finished.
- Switching model resets the context limit: the new model starts from its full window. The limit can be changed only when the turn has ended.

## `/reload` sent as a message, and messages refused during compaction

### Symptoms
- `/reload` appeared in the chat as a user message and did not reload Pi.
- A message sent while Pi was compacting failed with `Cannot submit a prompt while compaction is in progress`.

### Causes
- The composer recognized a command only if the command list was already loaded. `/reload` was also sent as a prompt and created a chat entry.
- Pi refuses prompts during a manual compaction, which is also the kind started by PiFrame's context limit.

### Fix
- Commands are a chip separate from the text and run without creating messages. The command list reloads every time the `/` menu opens.
- The daemon waits for the compaction to end (at most 10 minutes) before forwarding the message to Pi.

## Context unchanged after compaction

### Symptoms
After a compaction, the context indicator still showed the old value.

### Cause
Until the next answer, Pi reports the context tokens as unknown. PiFrame did not update the stats at the end of compaction and showed the tokens of the last answer, measured before the compaction.

### Fix
At the end of compaction PiFrame updates the stats and shows Pi's estimate (`estimatedTokensAfter`) until the real value arrives. If no estimate is available, it shows "post-compaction" instead of the old value.

## Subagent notification shown as raw XML

### Symptoms
The chat showed a `subagent-notification` card with the text `<task-notification>`, `<tool-use-id>`, `<status>` and so on, instead of the formatted notification card.

### Cause
The subagent result contained a code block (```` ``` ````). The chat split the message on code blocks before recognizing the notification, so the notification was broken up and shown as text.

### Fix
The chat now recognizes notifications before code blocks. The result, code block included, appears in the notification card. Update PiFrame to get the fix.

## Provider error before the answer: the message stays with no answer and no error

### Symptoms
After sending a message, it appears in the chat, the state goes back to «Completed», and neither an answer nor an error arrives. The message is not marked as failed and there is no «Retry» button.

### Cause
When the provider refuses the request (for example a rate limit, expired authentication, an unavailable model or a context that is too long), Pi ends the turn with an empty assistant message carrying `stopReason: error` and `errorMessage`. PiFrame recorded the reason only on an earlier assistant message. If there was none, the reason was lost.

### Fix
The error reason is now recorded on the user message, which shows the error border, the text «Send failed: …» and the «Retry send» button. If the answer started and then stopped, the text «Answer interrupted by an error: …» appears below the assistant message. A request stopped by the user is not reported as an error. Update PiFrame to get the fix.

## Error with a generic message: where to find the technical detail

### Symptoms

Git, the file list, the package list or another screen shows a short message such as "Operation failed" or "Could not load packages", without the technical error text.

### Cause

PiFrame turns internal technical errors (daemon unreachable, Git not installed, permission denied, timeouts and others) into a readable title and hint. Messages that the daemon or Pi send for the user (for example «Model unavailable» or a provider rate limit) are shown as they arrive. An internal Dart exception without a useful message shows only the generic title, and the raw text does not appear in pop-up messages.

### Fix

Provider and daemon messages are visible in the chat and on the screens. For internal errors, open the error box and press **Details**: the original technical text is selectable and can be copied into a report. If the error is recoverable, **Retry** repeats the operation. If the hint points to an outdated daemon, run `pnpm run build:agentd`, rebuild PiFrame and restart the daemon when no Pi worker is active.

## Session header: state and chips overlapping

### Symptoms

At 1584 px width, the state pill («Running» or «Completed») covered the start of the context chip («Context»), which was hidden.

### Cause

The context, cost and extension chips sat in a reversed horizontal scroll view: with little space, the first chip ended up under the state pill.

### Fix

The header row is now sequential: title and folder, then the state pill, then the chips. The chips start right after the pill and scroll horizontally when space runs out. At narrow widths the cost chip may stay out of view until you scroll. The `transcript_header_layout_test` test checks that the pill and the chips do not overlap at 480, 800, 1200 and 1584 px.
