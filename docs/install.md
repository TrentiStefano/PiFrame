# PiFrame Installation, Lifecycle and Uninstallation

This guide covers distribution, on-demand startup, updates and the safe uninstall procedure for **PiFrame**.

---

## 1. Distribution architecture (D8, D14)

PiFrame is a desktop application with two components, plus the Pi CLI it drives:
1. **Graphical interface (Flutter app)**: a desktop app for Windows, macOS and Linux. The local web build is still available from source.
2. **Runtime daemon (`pi-agentd`)**: a Node.js sidecar shipped in the installers together with the Node runtime. It manages the connection to Pi (`pi --mode rpc`), the event journal and session state.
3. **Original Pi CLI**: the Pi installation (`v0.85.0+`) stays fully external and untouched in `~/.pi/`. PiFrame **never changes, moves or overwrites** files inside `~/.pi/`.

---

## 2. System requirements

- **Supported operating systems**:
  - macOS 12+ (Apple Silicon `arm64` and Intel `x64`)
  - Windows 10/11 (`x64`)
  - Linux x64 (Debian/Ubuntu distributions with GTK 3)
- **Node.js**:
  - The installers include the Node runtime and the `pi-agentd` bundle; you do not need to install Node separately.
  - For development or running from source: Node.js ≥ 22.19.0.
- **Pi Coding Agent** (not included in the installer): minimum version **v0.85.0**, installed and on `PATH`. You can install it from PiFrame's first-run screen or with the official commands:
    - macOS / Linux: `curl -fsSL https://pi.dev/install.sh | sh`
    - Windows: `powershell -c "irm https://pi.dev/install.ps1 | iex"`
    - With npm: `npm install -g @earendil-works/pi-coding-agent`

### Dart/Flutter MCP for Pi

PiFrame uses the official built-in Dart/Flutter server, configured at user level in `~/.pi/agent/mcp.json` (`dart mcp-server`, deferred exposure). It needs the Flutter/Dart SDK on `PATH`. From the project root, check it with `pi mcp list`; the expected state is `dart · connected`. PiFrame starts RPC workers with the workspace as `cwd`, so the server attaches to the active project without needing local trust. Tools are discovered on demand through `tool_search`.

---

## 3. Installation

Download the latest installer from the [GitHub Releases page](https://github.com/TrentiStefano/piframe/releases/latest). Conventional commits (`fix`, `feat`, `BREAKING CHANGE`) update the SemVer release PR; when that PR is merged, GitHub Actions publishes the Windows, macOS Intel/Apple silicon and Linux x64 installers with an updated screenshot.

### macOS
1. Open the `.dmg` file and drag `PiFrame.app` into `/Applications`. The DMG window includes the step-by-step guides `README - How to open.txt` (English) and `LEGGIMI - Come aprire l'app.txt` (Italian).
2. On first launch, PiFrame starts `pi-agentd` with the Node runtime bundled in the package.
3. **Gatekeeper warning (Apple Developer ID and notarization):**
   - Apple requires a paid **Apple Developer Program** membership ($99 USD/year) to issue *Developer ID Application* certificates and to notarize with `notarytool`, so free open-source releases cannot be notarized at no cost.
   - The binary is signed ad hoc (`codesign --force --deep --sign -`) in the GitHub Actions build pipeline, so it runs correctly on Apple Silicon (`arm64`) and Intel (`x64`).
   - When you download the app with a browser, macOS adds the `com.apple.quarantine` attribute. To open it the first time, either:
     - **From System Settings (macOS 14 Sonoma / 15 Sequoia):** open PiFrame (Gatekeeper shows its message), go to **System Settings → Privacy & Security**, scroll to **Security** and click **Open Anyway**, then confirm with your password or Touch ID.
     - **From Terminal (quick command-line method):**
       ```bash
       xattr -cr /Applications/PiFrame.app
       ```
       This removes the quarantine flags from the PiFrame bundle, so it opens with a double-click.

### Windows
1. Run `PiFrame-Setup-…-windows-x64.exe`.
2. The installer adds Start menu shortcuts; the desktop icon is optional.
3. PiFrame bundles and starts `pi-agentd` with its own Node runtime and the Microsoft Visual C++ runtime (`msvcp140.dll`, `vcruntime140.dll` and so on) in app-local mode, so it also works on clean Windows installs. The installer is not signed, so SmartScreen may show a warning.

> [!TIP]
> **White window or frozen rendering?** With virtual display drivers (for example `USB Mobile Monitor`, `IddSampleDriver`) or multi-GPU setups, see [**docs/troubleshooting.md**](troubleshooting.md) for quick fixes.

### Linux (Debian / Ubuntu)
Install the downloaded `.deb` package:

```bash
sudo apt install ./PiFrame-…-linux-amd64.deb
```

The package adds PiFrame to the applications menu and includes the daemon and the Node runtime.

### Local web (`http://127.0.0.1:<port>/`)
1. The `pi-agentd` daemon includes a static HTTP server for the Flutter web assets.
2. When you open `http://127.0.0.1:<port>/` in a local browser, the server sets an `HttpOnly; SameSite=Strict` cookie with the PCP authentication token (`pcp_token`), so access works at once without manual setup.

### Development: desktop UI harness
To check the Flutter interface without touching a user's PiFrame session, use the isolated desktop harness: it runs the app off-screen with **fake-pi**. It is a developer-only tool.

From the monorepo root:

```sh
pnpm harness start
pnpm harness shot <label>
pnpm harness stop
```

To check every feature without a real Pi:

- `pnpm harness start --seed` creates isolated test data: a Git repository with changes, sessions (including a 150-message history and a hidden subagent), a pinned session and two MCP servers.
- `pnpm harness scenario <name>` changes fake-pi's behavior for the next prompt, without a restart. `pnpm harness scenarios` lists the scenarios, for example `provider-error`, `edit-files` (enables **Review changes**), `subagents`, `todos`, `ui-question-preview`, `session-tree`.
- fake-pi also answers `pi list/install/remove/update` and `pi mcp list`, so the Packages, Agents and MCP tabs show realistic data.
- `pnpm harness media --text-scale 1.4 --reduce-motion on` simulates text scaling and reduced motion. Harness runs start with animations on, even if the OS or an earlier run turned on reduced motion; `--reduce-motion system` follows those settings again.
- `pnpm harness record <label> [--duration ms] [--do "tap key:..."]` records an animation as numbered frames plus, with ffmpeg installed, a contact sheet (`sheet.png`) and a GIF, so you can review motion frame by frame.

Commands, selectors and details: [tools/harness/README.md](../tools/harness/README.md).

### Manual build from source (standalone executable)
If you build the desktop executable from source instead of using the installer (for example `flutter build windows --release`):
1. From the monorepo root, update the daemon first: `pnpm build:agentd` (or `pnpm build:all`). The Windows build refuses a bundle that is missing or lacks the fast index and the snapshot-cache response.
2. Build the Flutter app. CMake copies `apps/agentd/dist/pi-agentd.cjs` next to the executable. Also copy `node.exe` into the same folder if the Node runtime is not already there.
3. If the daemon is already running, let active workers finish and use **Settings → Restart daemon** to load the new bundle. Rebuilding the app does not stop a running daemon.
4. For details, or for file-lock problems (`EBUSY`), see [**docs/troubleshooting.md**](troubleshooting.md#4-daemon-unreachable-or-connection-error-with-a-source-build).

### Building the Windows installer locally (Inno Setup)
To build the full Windows installer (`dist/PiFrame-Setup-<version>-windows-x64.exe`) exactly as the GitHub Actions pipeline does:
1. Make sure **Inno Setup 6** is installed (for example with `winget install JRSoftware.InnoSetup`).
2. From the monorepo root, run:
   ```powershell
   pnpm run package:windows
   ```
   or directly with PowerShell:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools/scripts/package-windows-installer.ps1
   ```
   The script runs the whole sequence: it builds the TypeScript packages, creates the daemon bundle (`pi-agentd.cjs`), builds the Flutter Windows app and the web app for remote access, prepares the Node runtime with its licenses and builds the `.exe` setup in `dist/`. To repackage without rebuilding Flutter, pass `-SkipBuild`.

### Building the macOS installer locally (DMG)
To build the macOS disk image (`dist/PiFrame-<version>-macos-<arch>.dmg`) locally or fully offline:
> [!NOTE]
> Building the native macOS app (`.app`) and creating the compressed `.dmg` with the system tool `hdiutil` must run on macOS (with the Xcode Command Line Tools, the Flutter SDK and Node.js). Apple does not ship the proprietary Cocoa/Metal SDKs for Windows or Linux.

1. On a Mac, from the monorepo root, run:
   ```bash
   pnpm run package:macos
   ```
   or directly with the bash script:
   ```bash
   bash tools/scripts/package-macos-dmg.sh
   ```
2. The script runs the whole sequence:
   - Builds the `@piframe/pcp-ts` package and the daemon bundle (`pi-agentd.cjs`).
   - Builds the Flutter web app (`flutter build web --release`).
   - Builds the macOS app (`flutter build macos --release`).
   - Packages `PiFrame.app` with the bundled Node runtime, licenses and web assets.
   - Applies the ad hoc signature (`codesign`).
   - Adds the `/Applications` symlink and the guides `README - How to open.txt` / `LEGGIMI - Come aprire l'app.txt`.
   - Creates the compressed `dist/PiFrame-<version>-macos-<arch>.dmg` with `hdiutil` (fully offline).
3. **Useful script options:**
   - `--skip-build`: reuses the binaries already built and only regenerates the DMG.
   - `--build`: forces a full rebuild of every component even if the binaries exist.
   - Optional parameters: `bash tools/scripts/package-macos-dmg.sh [version] [architecture] [--skip-build]`.

---

## 4. Sessions with the same name and sidebar width

When sessions or repositories have equivalent names (ignoring case and spaces), PiFrame adds the parent folders needed to tell the paths apart. For example, two folders `v1/PiFrame` and `v2/PiFrame` are shown as **v1 / PiFrame** and **v2 / PiFrame**; if the parents match too, further ancestors are added. The distinction stays visible in the list, in pinned sessions, in Quick Launch, in the chat title, in the `/resume` picker and in notifications. Saved names and rename fields do not change; sessions in the same folder can still share a name.

Each session card shows what its agent is doing. A spinner and a coloured border mean the agent is working, even after you switch to another session. The dot on the left is a notification dot: it stays dark until the agent writes something you have not seen, then lights up until you open that session. A repository row and the **Pinned** header light their dot too when one of their sessions has news. Unread sessions are remembered across restarts in `~/.piframe/unread_sessions.json`. The outlined cursor on a card appears only while you move through the list with the keyboard.

Drag the divider on the right edge of the **Sessions** pane to make it wider or narrower. This works both in the sidebar on wide screens and in the panel opened with **Open sessions**. The width is saved with the layout in `~/.piframe/layout.json`, stays the same when you collapse and reopen the sidebar, and is clamped to the available space on small screens. In the browser the choice lasts for the current visit, like the other layout preferences.

## 5. Updating all Pi packages

In **Settings → Packages**, the update buttons are enabled only after PiFrame has verified that a newer installable version exists. **Update all** is enabled when at least one package meets that condition, and it updates, one after another, only the packages with updates available, using the Pi package manager. Packages that are already current, pinned versions, incompatible updates and unverified versions are left out. After you confirm, progress is shown; the update, remove and pin buttons stay disabled until it finishes. If one package fails to update, PiFrame continues with the others and shows a summary with the errors of the failed packages. The list is checked when the page opens and reloaded at the end: the buttons are disabled again when no updates remain. Restart Pi to load the updated code. Project packages are not changed.

The summary separates updates that were actually installed from packages that were already current and from pinned versions. For npm packages the daemon compares the version on disk with the version the configured source expects: without a version it uses `latest`; with a range or a tag it keeps that constraint. A command that exits with code zero but leaves an older version is reported as an error. Update, remove and pin also re-check the initial notice, so no stale data stays behind. On Windows the official standalone runtime in `%LOCALAPPDATA%\pi-node\current` is recognized too.

Before offering a newer npm version, PiFrame checks that it can be installed, including its required dependencies, with a dry run that runs no scripts. Versions not supported by the operating system do not trigger the update notice; the reason stays visible on the Packages page. The install, update and remove commands in the **Pi CLI** tab also re-check the list and the notice when they finish.

## 6. Pi slash commands in the chat

Type `/` in the composer to see Pi's built-in commands as well as those provided by extensions, prompts and skills. `/login` and `/logout` show the provider picker and use the Pi authentication flow; key and token fields are masked. Credentials stay in Pi's store, and these prompts are available only in the local app, not from remote clients. Other TUI commands that are not yet available over RPC show a notice and are not sent to the model. Update PiFrame to get the updated catalog and routing.

A command is never plain text:
- Pick a command from the `/` menu with a click, or with the `↑`/`↓` arrows and `Enter` or `Tab`. The command becomes a separate **chip** at the start of the composer, with its name, its source (`Pi`, `extension`, `prompt`, `skill`) and an entry animation.
- Only the arguments stay in the text field. The hint shows which arguments the command takes.
- If you type `/name` followed by a space, the command becomes a chip at once. If you send a hand-typed `/name`, the first `Enter` turns it into a chip and the second runs it.
- `Enter` runs the command: while it runs, the chip shows a progress indicator.
- Pi and extension commands (for example `/reload` or `/caveman full`) do not create chat messages. Prompts and skills become a normal user message instead.
- `Backspace` in an empty field, or the `×` on the chip, removes the command. Without arguments, `/name` goes back into the field as editable text.
- Text that contains a `/` without a chip (for example `why does /reload fail?`) is sent as a normal message.

## 7. Sending messages with Enter (Send with Enter)

In **Settings** (**Appearance → Composer**) there is a **Send with Enter** option (off by default):
- **Off (default)**: `Ctrl+Enter` (or `Cmd+Enter` on macOS) sends the message or applies the steer; `Enter` inserts a new line in the composer.
- **On**: `Enter` (or the numeric keypad `Enter`) without modifiers sends the message (or applies the steer while the agent is answering); `Ctrl+Enter` / `Cmd+Enter` still sends; `Shift+Enter` inserts a new line.
- While an IME composition is active (for example CJK input), `Enter` confirms the text without sending, in both modes.
- The preference is saved locally in `~/.piframe/composer_settings.json`.

## 8. Keyboard shortcuts

On macOS `Cmd` replaces `Ctrl` unless noted. Shell shortcuts (rows marked "Shell") apply when no text field, composer, editor or terminal handles them first.

| Shortcut | Action | Where |
|---|---|---|
| `Ctrl+N` / `Cmd+N` | New session (opens the folder picker) | Shell |
| `Ctrl+,` / `Cmd+,` | Open Settings | Shell |
| `Ctrl+B` / `Cmd+B` | Show or hide the sessions sidebar; in a narrow window, open or close the sessions drawer | Shell |
| `Ctrl+Tab` | Go back to the previously active session (if it still exists) | Shell |
| `F6` / `Shift+F6` | Move focus to the next or previous pane (title bar, sessions, repository, chat, companion pane) | Shell |
| `Ctrl+1` … `Ctrl+4` / `Cmd+1` … `Cmd+4` | Move focus to sessions, repository, chat (composer) and the companion pane | Shell |
| `Ctrl+K` / `Cmd+K` | Open the Command Palette | Shell |
| `Ctrl+Shift+B` / `Cmd+Shift+B` | Open or close the session's side conversation | Shell |
| `←` / `→` with focus on a divider | Move the divider by 20 px (sessions sidebar and dividers between panes); dividers take focus with `Tab` | Dividers |
| `Ctrl+F` / `Cmd+F` | Search in the file open in the repository editor | Editor (Repository pane) |
| `Ctrl+G` / `Cmd+G` | Open *Go to line* | Editor (Repository pane) |
| `Ctrl+S` / `Cmd+S` | Save the open file | Editor (Repository pane) |
| `Enter` / `Ctrl+Enter` / `Cmd+Enter` | Send the message; depends on *Send with Enter* (see above) | Composer |
| `Shift+Enter` | New line in the composer (with *Send with Enter* on) | Composer |
| `Tab` / `Enter` | Accept the selected slash command or mentioned file | Composer |
| `↑` / `↓` | Move through slash commands, mentioned files and suggestions | Composer, file picker, Command Palette, branch picker |
| `Enter` | Confirm in the Command Palette, the branch picker and session rename | Palette, branch picker, session rename |
| `Shift+F10` / Menu key | Open the context menu of the focused row (or the cursor row) in the sessions list, the Git list and the file tree | Sessions, Git, Repository |
| `F2` / `Enter` on the session title | Rename the session (like double-clicking the title) | Session header |
| `F2` on the selected session row | Rename the session under the list cursor (not for folders) | Sessions |
| `Enter` on a session or folder row | Open the session, or expand or collapse the folder | Sessions |
| `Enter` on an unsent message | Put its text and attachments back in the composer (like double-clicking) | Chat |
| `Esc` | Close the topmost layer, in this order: menu, dialog, drawer (sessions or context), diff in the pane, Review mode, Settings. It stops the agent only when no layer is open and the composer has focus during a run | Shell (uniform) |
| `Tab` / `Shift+Tab` | Focus order: title bar, sessions, repository, chat, composer, companion pane; top to bottom inside each pane | Shell |
| `←` / `→` | On the companion pane tabs (Files, Review Changes, Chat): select the previous or next tab; `Enter` or `Space` selects the focused tab | Companion pane |
| `Enter` / `Ctrl+Enter` / `Cmd+Enter` | Send in the side conversation pane (according to *Send with Enter*) | Side pane |
| `Ctrl+C`, `Ctrl+L`, `Ctrl+V` | Interrupt, clear the screen, paste in the terminal | Integrated terminal |
| Arrows, `Tab`, `Enter`, `Backspace` | Sent to the integrated terminal's shell | Integrated terminal |

**Resolved conflicts.** The composer and text fields handle `Tab` and `Enter` before the shell, so `Ctrl+Tab` is not used while the slash command menu is open. The integrated terminal handles `Ctrl+C`, `Ctrl+L`, `Ctrl+V` and `Tab` first, so they stay with the terminal. `Ctrl+Shift+B` keeps its existing meaning (side conversation) and no longer opens the sessions sidebar, which stays on `Ctrl+B`.

### Title bar

The title bar has two groups separated by a thin vertical line:

- **View**: the menu to show or hide panes (from 900 px, with a session open) and the light/dark theme switch.
- **Workspace**: the **Session** button (model, context and branches of the session) and **Settings** (`Ctrl+,` / `Cmd+,`). From 1100 px the Session button shows its label; below that width it is an icon with a tooltip.

The daemon connection state sits on the left next to the brand mark. From 920 px it shows the dot and the label (*Local Pi* or *Not connected*); below 920 px only the dot remains, with a tooltip and a screen-reader description. A click opens **Settings → Diagnostics**.

## 9. Agents and Workflows pane

When the main agent starts background subagents (`Agent`) or workflows (`SubagentWorkflow` from `@tintinweb/pi-subagents`), the **Agents** pane opens to the right of the chat. When the pane opens, also when you enter a session where it was already open or with agents at work, the Git Changes/Browser pane is minimized; during a review it stays visible. When closed, the pane remains a vertical strip with the number of active agents; a click reopens it. The pane does not appear below 900 px of width.

The pane shows agents as a tree starting from the **Main session**:

- **Workflows**: name, state, duration, a bar with one segment per agent (green finished, colored working, red error) and the phases declared in `meta`. The workflow's child sessions, that is the agents started while the workflow was active, hang below it. The script path is not shown. Expanded, it shows the description and the final result; if the daemon does not provide child sessions, the desktop app uses the `<runId>.workflow.jsonl` journal.
- **Agents**: task (for workflow agents, the first line of the prompt that they do not share with the others, for example `TASK: …`), type, model, cost (or `N/A`), duration and current activity: the tool in use with its main argument while it works, the last line of the answer when it has finished. Active branches have an animated ring and a spark running along the connector. Expanded, an agent shows its output; `Agent` agents also have steer and interrupt.

The state comes from pi-subagents itself: PiFrame's extension in the Pi worker reports the agents' live status, so the pane matches `/agents`. Activity and output are read from the session files of child sessions (`~/.pi/agent/sessions`). For a session PiFrame is not running (for example, open in a Pi terminal), the pane falls back to those files: a child session with no activity for 10 minutes is considered finished. This needs an up-to-date daemon: with an older daemon the pane shows only name and state.

**Stop** on an agent stops it through pi-subagents' own stop, the same as `/agents`, and the pane says so if it could not. The main agent also has a `stop_subagent` tool, so you can ask it to stop an agent. A running agent whose session has not moved for 10 minutes shows *No activity for N min, it may be stuck*: usually a tool call that does not return; stop it, or steer it. PiFrame no longer stops an idle Pi worker while one of its background agents is still running.

### Tasks tab

The agent's task list (todos) lives in the same pane, as a **Tasks** tab next to **Agents** and **Side**, instead of a popup over the chat. The tab shows how many tasks are done (`Tasks (3/5)`). The pane's header lists its tabs and, on the right, one **>** button that hides the whole pane, whichever tab is showing; the tabs have no close buttons of their own. When the agent adds tasks, the pane opens on the Tasks tab, unless a side conversation is open there; once you hide the pane, new tasks no longer reopen it in that session. In the tab you can tick tasks, expand one to read its description, and add your own with **+**. When the pane is hidden, its strip reopens the last tab you used. An unsent message in the Side tab is kept when you hide the pane or switch tab.

Drag the thin line between the chat and the pane to make the pane wider or narrower.

In the `/agents` menu, **Workflows (N)** opens this pane instead of the TUI view, which is not available over RPC. In the Sessions sidebar, a session stays marked as running until its background subagents or workflows finish.

## 10. Technical stats and resource monitoring

In **Settings** (**Appearance → Technical stats**; called *Nerd stats* in older versions) you can turn on real-time system telemetry in the app's title bar (off by default):
- **Off (default)**: the title bar shows no hardware metrics or frame counters, and no subscription command is sent to the daemon.
- **On**: a compact monospace box in the top bar shows:
  `CPU 12.3% · RAM 48% · DISK 62% · GPU n/a · 60 FPS`
  Hovering the widget shows a detailed tooltip with exact RAM use (used / total and percentage), disk space on the user's main volume (used / total and percentage), GPU use with VRAM and the detection source, and the rendering frame rate.
- **Warning thresholds**: when a resource goes above 85% use, its percentage takes the active theme's warning color.
- **Unavailable or stale data (`n/a`)**: if a hardware sensor or metric is not available on the host, or no sample arrives from the daemon for more than 5 seconds (or the connection drops), the value is shown as `n/a`; PiFrame never makes up data.
- **FPS counter**: measured on the client from Flutter's rendering timings (`SchedulerBinding.instance.addTimingsCallback`). When the app is idle or needs no redraw, the engine renders nothing extra and the counter correctly reports a low value or zero frames in the last second. The stats UI refreshes at most at 1 Hz to avoid constant rebuilds.
- **On the web**: in the web interface (`http://127.0.0.1:<port>/`) the system metrics (CPU, RAM, disk, GPU) stay hidden for security reasons and because the browser has no direct hardware access; **only the FPS segment** of the client's own rendering is shown.
- **GPU support per platform (`pi-agentd` daemon)**:
  - **NVIDIA**: supported everywhere through `nvidia-smi` (Windows, Linux, macOS).
  - **Windows (DirectX / GPU engine)**: supported through `typeperf` performance counters (only with an English system locale; on Windows installs in other languages, where counter names are localized, the GPU shows `n/a`).
  - **Linux (AMD)**: supported through `sysfs` (`/sys/class/drm/card*/device/gpu_busy_percent`).
  - **macOS (Apple Silicon / Metal)**: supported through `ioreg` (`PerformanceStatistics`).
  - **Other cards or environments without a supported probe**: shows `n/a`.
- **Zero telemetry (strict local-only)**: resource sampling happens only locally, over the PCP protocol (`system.metrics.subscribe` and `system.metrics`) between the local `pi-agentd` daemon and the Flutter client. No metric or telemetry data is stored permanently or sent out. The preference is saved locally in `~/.piframe/nerd_stats_settings.json`.

## 11. Enabled models and context limits

In **Workspace → Session → Context size**, choose a tier or **Custom**. For GPT-6 Luna the options are `Custom`, `272k (base tier)` and `1M (max / extended tier)`, unless the provider catalog declares different thresholds. Only Custom shows the maximum-window slider: **100,000–1,000,000 tokens**, in steps of **50,000**. The maximum is always reduced to the model's capacity and to the available grid; below 100k Custom is not available. Provider tiers keep their exact value, even when they are not multiples of 50k.

The context chip in the chat opens the same picker, with tiers and Custom kept in sync with Workspace. If the catalog was not available yet at first launch, the click reloads it; an error is shown, not ignored. The sliders show the value while dragging and apply it on release, so there is no request for every movement.

The **Compaction margin (%)** slider goes from **0.5% to 25%**, in steps of **0.5%**. It is the share to keep free, not the share to fill:
- 200,000 tokens, default margin 2.5% → threshold 195,000 tokens.
- 1,000,000 tokens, margin 5% → threshold 950,000 tokens.

PiFrame applies the threshold to the Pi runtime, including between tool continuations; at the end of a turn it compacts if the threshold was reached. There are no longer separate 80% controls in the GUI. Automatic compaction that is disabled in Pi stays disabled. Wait for the turn to finish before changing these values. The limit and margin are saved per session in `~/.piframe/context/`, restored when the session reopens and copied into duplicates. When you switch to a smaller model, the limit is reduced to its maximum.

The control uses an internal extension loaded only in PiFrame workers; it does not install `max-context` and does not change settings or credentials in `~/.pi/`. It needs Pi's `getSettings` extension API, verified with **Pi 1.4.0**. If your version does not support it, the app reports that the limit was not applied: update Pi and restart the worker.

Like [max-context](https://github.com/indie-arch/max-context), it is a preventive check based on token use and estimates, not an accounting guarantee on cost. A single input, tool output or answer can exceed the margin before the next check, and the summary request uses tokens too. Use a wider margin for tools with large outputs. Very low limits may not fit the system prompt, the tools and the recent messages Pi keeps.

The GitHub Copilot picker checks the authenticated catalog and the organization's policies before applying any local `enabledModels` filters. It does not enable models or change GitHub policies. If the check fails, unverified Copilot models stay hidden and a notice appears; other providers stay available. A successful check is cached briefly: a policy change can take up to a minute to show.

---

## 12. Daemon lifecycle (D8, D9)

- **On-demand startup**: the daemon is not a persistent system service. The GUI checks `GET http://127.0.0.1:<port>/api/health`; if the daemon is not running, it starts the `pi-agentd.cjs` bundle with the bundled Node runtime in `detached` mode.
- **Lock and token**:
  - Runtime file: `~/.piframe/runtime/daemon.json` (port and PID).
  - Lock file: `~/.piframe/runtime/daemon.lock`, to prevent duplicate instances.
  - Authentication token: 256 bits, in `~/.piframe/runtime/daemon.token` with restricted permissions (0600).
- **Rotating log**:
  - Log file: `~/.piframe/runtime/daemon.log`.
  - Automatic rotation across 5 files of 5 MB each.
- **Worker idle timeout (D9)**:
  - Configurable idle timeout (default 30 minutes, adjustable in Settings).
  - Running workers (`working`, `retrying`, `compacting`, `awaiting_user`) are **never** stopped for inactivity.

---

## 13. Upgrades

- At startup, the GUI reads the running daemon's version through `GET /api/health` and compares it with the version of the binary in the bundle.
- If the versions differ, the GUI tells the user and offers a controlled daemon restart, only when no worker is active.

---

## 14. Uninstallation

Removing PiFrame is clean, contained and reversible:

1. **Remove the GUI app**:
   - macOS: move `PiFrame.app` to the Trash.
   - Windows: uninstall it from Settings → Apps (or delete the application folder).
2. **Stop the daemon** (if running):
   - End the `pi-agentd` process from the task manager or with `kill <PID>`.
3. **Delete PiFrame's local data**:
   ```bash
   # macOS / Linux
   rm -rf ~/.piframe

   # Windows PowerShell
   Remove-Item -Recurse -Force "$HOME\.piframe"
   ```

### Integrity guarantee for `~/.pi/`
> [!IMPORTANT]
> PiFrame is strictly non-invasive. Pi's directory (`~/.pi/`), with the session history, credentials and extensions, **is never touched or removed**.
> All original sessions stay fully usable from the official Pi CLI after PiFrame is uninstalled.

---

## 15. History pagination and on-demand loading

In sessions with a very long history (thousands of messages or large tool logs):
1. **Light initial snapshot**: when a session opens, the daemon sends a recent window limited to the latest 100 messages, so loading is instant and RAM and WebSocket buffers stay light.
2. **On-demand backward loading**: at the top of the chat, the *Load earlier messages* button fetches further blocks of older messages with the `session.getHistory` command, keeping the scroll position without visual jumps.
3. **Complete integrity**: the full history stays on disk in `~/.pi/agent/sessions/` and can be browsed backward step by step, down to the very first message of the session.

---

## 16. Git branch navigation and switching in the workspace

The PiFrame runtime (`pi-agentd`) supports inspecting and switching Git branches in a controlled way (`workspace.listBranches` and `workspace.switchBranch`):
- **Listing and tracking**: returns every local branch with a marker for the current one, its upstream tracking state (`ahead` / `behind`), the date of the last commit, and detection of a detached HEAD.
- **Overwrite protection**: switching refuses a dirty working tree (`onDirty: 'block'`, the default) and reports the exact number of changed and untracked files. With `onDirty: 'stash'`, pending changes are stashed safely (`piframe: before switching to <name> (<iso time>)`) before the switch, and restored with `git stash pop` if the checkout fails.
- **Isolation and safety**: the commands are confined to the current session's repository, run without a shell (`shell: false`) with array arguments, are protected against injection through invalid branch names, and are refused for read-only sessions or while the agent is working.
- **User interface (branch picker and change handling)**: in the Git Changes pane, the current branch is an interactive chip (with an icon and the commit SHA on a detached HEAD). Clicking it opens a quick picker with search, keyboard navigation (arrows, Enter, Esc) and tracking state (↑n ↓m). If there are uncommitted files, a safety dialog blocks the switch and asks for explicit confirmation to stash or cancel, with clear notices and details on errors or stash recovery.
- **Fetch / Pull / Push / Sync**: at the bottom of the Git Changes pane, four buttons run `workspace.gitAction` with the action `fetch` (`git fetch --all --prune`), `pull` (fast-forward only: a diverged history is refused, never merged silently), `push` (a branch without upstream is published to `origin` with `--set-upstream`) and `sync` (pull, then push). Like every repository write, they are disabled for read-only sessions or while the agent works. The daemon never opens credential prompts in the terminal (`GIT_TERMINAL_PROMPT=0`), and Git errors appear in a notification.
- **Diff in the pane**: selecting a file replaces the list in the Git Changes pane with its diff, and the chat stays visible above. The header shows "← Changes", the file name, the position (for example 2/5), previous and next file buttons, Stage or Unstage, Discard… and "Open in window", which shows the diff in a wider window. Keyboard: Enter opens the file under the cursor in the list; Alt+↓ and Alt+↑ move to the next or previous file, without animation; Esc or Alt+← go back to the list. Below 900 px the diff fills the whole pane.
- **Inline commit**: you write the commit message directly in the Git Changes pane, above Fetch, Pull, Push and Sync, without a separate window. The subject is one line with a counter that references 72 characters; past that limit the counter switches to the warning color, but the commit is still allowed. The description is optional and opens with "Add description". The Commit button stays disabled while the subject is empty. Ctrl+Enter (Cmd+Enter on macOS) commits from the fields. In the compact layout (below 900 px) the Commit button takes the full width, below the four Fetch, Pull, Push and Sync buttons. After the commit, a notice shows the short hash of the new commit; if the commit fails, the error appears in the form and the message is kept.
- **Actions on Git rows**: stage, unstage and discard appear on hover or when the row has keyboard focus. Where there is no pointer (compact layout below 900 px, iOS, Android and the web on mobile devices) they are always visible.

---

## 17. Step grouping

PiFrame shows the intermediate steps the assistant takes during a turn (thinking blocks, tool calls and intermediate text) in a compact, readable way, and keeps the final answer prominent:

- **Step grouping modes**:
  - **Full (`full`)**: an ultra-compact chat. All intermediate steps, thinking blocks and non-final answers of the agent are grouped into one collapsed, expandable block: the chat shows only the user prompt, an indicator with the number of steps and the time taken, and the agent's final answer. While running, only the title of the last active step is shown, with a loading indicator and a cross-fade between one step and the next.
  - **With thinking (`withThinking`, default)**: automatically groups turns that contain thinking blocks (both in history and while streaming).
  - **Always (`always`)**: groups every turn that has at least one intermediate step (thinking, a tool call or intermediate text).
  - **Off (`off`)**: turns grouping off; every message, tool call and thinking block appears on its own in the normal chat flow, pixel-identical to the classic view.
- **Auto-collapse (on by default)**:
  - When a turn ends or a session opens, the grouped intermediate steps collapse automatically, showing a short header with the number of tools used, the elapsed time and an excerpt of the thinking.
  - Clicking the header, or pressing Enter/Space when it has focus, expands or collapses the accordion with a smooth animation.
  - The user preference (grouping mode and auto-collapse) is saved locally and remembered across sessions.
- **Compact step list**: an expanded group takes at most half the window height. If there are more steps, the list scrolls inside it (while running, it follows the last step if you are already at the bottom). At the bottom, **Show all steps (N)** expands the list to full height. When the group is collapsed (by hand or at the end of the turn) and opened again, the compact list comes back.
- **Turn state**: a turn that reaches its final answer shows *Completed N steps*, with a warning icon if a step failed. *Stopped with errors* appears only if the turn itself ended in an error; *Stopped after N steps* if the user stopped it. The final answer always stays outside the group.
- **Working header**: while a group is running, its header text has a slow shimmer and a three-dot progress indicator. Under *Reduce animations* (and in widget tests) the shimmer stops and the text is drawn in the theme's primary text color.

---

## 18. Subagents and context limits (Subagents settings)

PiFrame supports inspecting and configuring subagents (`pi.agents.get` and `pi.agents.update`):
- **Package and profile auto-discovery**: detects installed subagent packages (`pi-subagents` by nicobailon and `@tintinweb/pi-subagents`), built-in agents, user agents in `~/.pi/agent/agents/` and project agents in `.pi/agents/`.
- **Effective value resolution**: works out the effective model and thinking level of each agent, with its exact origin (`override`, `frontmatter`, `default` or `none`) and its availability with the active credentials.
- **Where per-agent overrides are written**: with `pi-subagents` (nicobailon) the Model and Thinking overrides go to `subagents.agentOverrides.<name>` in `~/.pi/agent/settings.json`. `@tintinweb/pi-subagents` reads a subagent's model and thinking only from the agent file's frontmatter, so with tintinweb installed PiFrame rewrites the `model:` / `thinking:` line of user agents in `~/.pi/agent/agents/*.md`. Every other byte of the file stays as it was, a `<file>.piframe-backup` copy is made before each write, and the replaced line is recorded in `~/.piframe/subagent-frontmatter-originals.json`, so *Reset* puts the original line back (or removes the line if the field was absent). Package and project agents stay read-only. tintinweb has no per-agent context limit, so the Context control shows `n/a` with that reason.
- **Per-agent context limits**: you can set context-window limits (cost tiers) for each subagent. The daemon generates a small, isolated extension in `~/.piframe/runtime/subagent-context-limit.mjs`, hooked through `subagentOnlyExtensions`, which adjusts the model's context window only when that subagent starts, without touching the main session or the installed binaries. *(Note: before uninstalling PiFrame or removing `~/.piframe`, reset the context limits in the Agents tab, or remove the path from `subagents.agentOverrides.<name>.subagentOnlyExtensions` in `~/.pi/agent/settings.json`, to avoid `ERR_MODULE_NOT_FOUND` errors the next time Pi CLI starts subagents.)*
- **Safe writes and a compatible lock**: changes to `settings.json` take a lock compatible with Pi's `proper-lockfile` (stale-lock detection after 10 seconds), create an automatic `settings.json.piframe-backup` and write atomically. Invalid JSON files are refused (`AGENTS_CONFIG_UNREADABLE`) and remote devices cannot change anything (`REMOTE_FORBIDDEN`).
- **User interface (Settings → Agents tab)**:
  - **Header and packages**: the detected packages with their version (`pi-subagents`, `@tintinweb/pi-subagents`). If no package is installed, a banner explains how to install one from the CLI (`pi install pi-subagents`) or from the Packages tab, without made-up lists. Configuration warnings from the daemon are highlighted. A note reminds you that changes apply globally to Pi (from the terminal too) and to new sessions and subagent runs.
  - **Defaults for new sessions card**: picks the default model for primary Pi sessions (the dropdown lists only available models, with a warning when credentials are missing) and the thinking level (limited to `off` if the model does not support reasoning). A dedicated *Reset* button removes the default.
  - **Subagent defaults card**: global subagent defaults (model and thinking for `pi-subagents`, or the fallback agent for `@tintinweb/pi-subagents`), with reset buttons and warnings for unavailable models.
  - **Agent list**: every discovered agent, with a source badge (`builtin`, `user`, `project`, `package`), description, effective model with an origin badge (`override`, `frontmatter`, `default`), effective thinking and a context-tier picker (for example `272k`, `1.05M (full)`) only when supported (otherwise `n/a` with the tooltip *Model has a single context tier*). Agents that cannot be edited (for example external CLI runners, project or tintinweb agents) are disabled, with a tooltip showing the `readOnlyReason`. Every field has a *Reset* button that sends `null` to clear the override.
  - **Save bar and remote safety**: a *Save changes* button (enabled only when there are unsaved changes), a *Cancel* button to discard local changes, inline per-field validation errors (`AGENTS_VALIDATION_FAILED`), a success snackbar, and a read-only lock with a notice for remote access (`REMOTE_FORBIDDEN`).

---

## 19. Read-only side conversations

PiFrame supports short-lived, read-only side conversations (`side.open`, `side.prompt`, `side.abort`, `side.close`):
- **Read-only consulting assistant**: ask follow-up or clarifying questions ("Explain this function", "Review the tests", "Which constraints came up?") on an immutable snapshot of the main conversation; the assistant can read the workspace files.
- **Strict isolation of the transcript and the session**:
  - The main session file in `~/.pi/agent/sessions/` is never changed or rewritten; it is byte-for-byte identical before, during and after every side operation.
  - No side conversation event reaches the main session's event journal.
  - Side conversation events travel on a dedicated stream (`streamId = side_<ulid>`) and are kept only in an in-memory ring buffer for the daemon's lifetime, so clients can reconnect; nothing is spilled to disk.
- **Strictly limited tools (`read, grep, find, ls`)**: the side worker starts with `--tools read,grep,find,ls`, `--no-mcp`, `--no-extensions` and `--no-skills`. Write and mutation tools (`bash`, `edit`, `write`) are excluded, and the daemon blocks every RPC call other than `prompt`, `abort` or `get_state` (`SIDE_RPC_BLOCKED`). If the worker exposed disallowed tools at startup, it would be terminated at once with `SIDE_UNSAFE_TOOLS`.
- **Careful snapshot and automatic cleanup**:
  - The active conversation is serialized, with a guardrail preamble, to `~/.piframe/runtime/side/<sideId>/context.md` (directory `0700`, file `0600`) and passed with `--append-system-prompt`.
  - The snapshot is capped at about 120,000 characters, keeping the most recent exchanges and adding an explicit truncation notice when the cap is reached.
  - The temporary directory is deleted when the side conversation closes or the daemon stops.
- **Concurrency and safety rules**:
  - At most 1 active side thread per parent session (further calls return the existing thread).
  - At most 4 side threads active at the same time on the whole host (`SIDE_LIMIT_REACHED`).
  - Idle timeout after 10 minutes (`reason: 'idle'`), with the worker stopped automatically.
  - Immediate termination when the parent session closes (`reason: 'parentClosed'`).
  - Remote connections: opening and prompting need `control` mode (`REMOTE_FORBIDDEN` in `view`), while abort and close are allowed in `view` mode too. Any other command sent to the side stream is rejected with `SIDE_STREAM_READ_ONLY`.
- **User interface and client commands (Flutter)**:
  - **Built-in slash commands**: `/side [question]` and `/btw [question]` are handled locally by the composer (never sent as prompts to the main agent). They appear in the slash menu with the description *"Read-only side conversation"*.
  - **Keyboard shortcut and Command Palette**:
    - Global shortcut: `Ctrl+Shift+B` (Linux/Windows) or `Cmd+Shift+B` (macOS) opens or closes the side pane in the current session.
    - A dedicated Command Palette entry (`Ctrl+K` / `Cmd+K`): *"Side conversation"*, with `Ctrl`/`⌘` + `Shift` + `B` shown on the right.
    - The Command Palette groups commands into Session, View, Git and Settings, shows only the commands that apply (for example *"Stop agent"* only while the agent works), closes itself before running the command and includes *"Go to session…"* with fuzzy search across sessions.
  - **Docked side pane (side panel and companion sidecar)**:
    - Side discussions (`/side` and `/btw`) live in the companion sidecar to the right of the chat, next to the Agents pane, resizable by dragging (240–700 px).
    - Full history of the session's discussions (`SideConversationRecord`): every side discussion started in the session is kept and can be browsed through a horizontal pill selector, with an active/closed/error indicator and deletion on request.
    - A `+` button in the header starts a new side discussion at any time.
    - Escape or X closes the pane. A confirmation appears only if the mini composer holds a draft. Ctrl+Shift+B opens or closes the pane instantly.
    - The header has a `Side · read-only` badge, the active model chip, the discussion count and the note *"Not part of the main conversation"*.
    - A mini transcript reuses the `RichContent`, `ThinkingBlock` and `ToolCard` components for the selected discussion.
    - A mini composer for follow-up questions, honoring the Send with Enter preference.
    - A **Stop** button (`side.abort`) interrupts the running answer, and a **Close** button (`side.close`).
    - An **"Insert into composer"** action on each assistant answer appends its text to the main composer draft, only on an explicit click.
    - Thread close reasons (`idle`, `parentClosed`, `error`, `user`) are handled with a dedicated notice banner.

---

## 20. Interface language (Italiano / English)

In **Settings → Appearance → Application Language** you can choose **Italiano** or **English**. The choice applies to the whole interface: title bar, Sessions sidebar, Repository, chat and grouped steps, composer, Workspace pane and context picker, Git Changes, change review, integrated browser, terminal, Agents pane, side conversations and Settings. Only a few error and update messages stay in Italian.

- **Desktop app**: the choice is saved in `~/.piframe/language_settings.json`. The default is still Italian.
- **Web and phone (remote access)**: the web client cannot read `~/.piframe`, so it saves the choice in the browser's `localStorage`. If you have never picked a language, the web client follows the browser language: Italian for `it-*`, English for everything else.

## 21. Integrated terminal: aligned Git output

Integrated terminal processes use pipes, not a pseudo-console. Tools such as `git` write lines that end with LF only, which used to be shown as a "staircase" (each line started at the column where the previous one ended). PiFrame now converts every lone LF to CRLF before writing to the terminal, including stderr and when a CRLF is split across two output chunks. Commands such as `git branch` or `git log --oneline` are therefore shown aligned.

## 22. Mobile web app: reliable startup, aligned taps and better speed

The web app opened from a phone (remote connection) is sturdier and lighter:

- **No blank background**: before downloading the app, the browser checks the device credential. If the phone is no longer paired it shows "Pair the device again"; if the computer cannot be reached (PiFrame closed, Tailscale off on the phone) it shows a message and retries every 5 seconds. A watchdog offers *Reload* if the app does not start within 30 seconds.
- **Persistent pairing**: the device cookie now expires after 30 days (renewed on each visit) instead of being a session cookie, which iOS deletes when the browser closes.
- **No stale cache after updates**: the daemon serves web files with `ETag` and revalidation, and turns off Flutter's service worker (removing those installed by older versions).
- **Faster loading**: web files are compressed with Brotli/gzip, large WebSocket frames use `permessage-deflate`, and the daemon no longer runs `tailscale status` synchronously on every state update (it blocked every client).
- **Aligned taps**: the page is locked (no scroll, no pinch or double-tap zoom) and the leftover iOS scroll after the keyboard closes is reset, so taps match what is drawn.
- **Less lag on phones**: on narrow web screens the animated intro and the composer's animated glowing border are off; the release build uses `--pwa-strategy=none`.
- **Compact composer on phones**: below 600 px the model and effort pickers show only their icon (name and arrow hidden, tooltip unchanged). The "expand" button over the text does not appear on phones.
- **Smoother sessions drawer**: on narrow web screens the "working" indicator of sessions is static (no animated blurred glow that repainted the list on every frame).
- **Always-current web folder**: the app and the daemon pick the most recently built copy of the web app (build/web, next to the executable, ~/.piframe/web) instead of the first one found, so the phone never gets an old build.
- **Diagnostics**: opening the web app with `?pfdebug=1` shows a strip with the viewport and the coordinates of the last tap; the daemon logs how many paired devices it loaded or discarded and saves `remote_devices.json.bak` on the first write.
- **Steps block collapsed on phones**: below 600 px the intermediate steps block starts closed even while the agent works (a tap opens it), to leave room for the conversation.
- **File and image upload from phones**: in the browser, the chosen file is uploaded to the computer (`POST /api/blobs`, needs `control` mode, max 50 MB) and the prompt carries its absolute path on the host (`~/.piframe/blobs/<id>/<name>`), so the agent can read it. Before, only a `blob:` URL was sent, which is valid only inside the browser, so the attachment never arrived. Sending stays blocked until uploads finish; files are deleted after 14 days.
- **No iOS zoom while typing**: Safari zooms the page by about 10% when you tap a field whose text is smaller than 16 px (the composer uses 14.5 px), which cut off the header and buttons. Flutter's hidden editing element now uses 16 px, and if the page still stays zoomed after the keyboard, it is reset to 100%.
- **Composer within the space above the keyboard**: the composer height (text, attachments and the button row) is limited to the space really available above the keyboard, so a long message scrolls inside the field without pushing the buttons off screen. The composer border while the agent answers is thinner and softer on phones.
- **Concentric corners on iPhone (iOS guidelines)**: on phones with rounded corners, the bottom edges follow the display curve like native apps: pane radius = display radius − margin (8 px), and composer radius = pane radius − composer margin. A web page cannot read the display radius, so it is estimated from the width (375 pt ≈ 40, 390 pt ≈ 47, 393/430 pt ≈ 55). With the keyboard open, or in a Safari tab with a toolbar, the normal corners come back.
- **Text selection and caret on iPhone**: composer text on phones is 16 px (same 21 px line) so that Flutter and the hidden native field wrap lines the same way; before, with different fonts, moving the caret with the space bar or selecting by line ended at different places from those shown. The selection color is more visible (opacity 0.4 instead of 0.2), and caret-only moves no longer rerun the slash/@-mention logic (a setState and a focus request on every move).
- **Tunnel restart**: if the tunnel does not start when the daemon starts (for example Tailscale is not ready yet), the daemon retries with backoff up to 60 seconds.

## 23. Reduced motion (Reduce animations)

Settings → **Appearance** → **Reduced motion** → *Reduce animations*.

- With the switch on, PiFrame stops moving elements: panes and rows appear with a fade, decorative loops (the composer's active ring, the dot of running sessions, the subagent animation) become static, and expand animations are short fades.
- The preference is saved in `~/.piframe/reduced_motion_settings.json` and applies to every session.
- The operating-system setting that asks to *reduce or remove animations* (macOS: Reduce motion; Windows: Animation effects off) is honored too. The two sources combine: either one turns reduced mode on.
- Circular working indicators become a static sync icon of the same size, so nothing spins on screen. Indeterminate progress bars in Settings → Packages and Updates become a full, still bar; a bar with a known percentage keeps showing it.

Normal motion: while the agent works, the composer ring runs around the border in a loop (3.6 s per lap) and stops when the work ends. Panes, rows and intermediate steps use short durations (120–240 ms) with exit curves.

## 24. Startup animation

Settings → **Appearance** → **Startup animation**.

- The first time PiFrame opens, you see a startup animation of about 1.4 seconds, with audio. Later launches show the app at once with a short fade (620 ms).
- With the switch on, the animation with audio plays again on every launch.
- The preference is saved in `~/.piframe/startup_animation_settings.json`. The first-run flag is in `~/.piframe/app_first_run.json`.
- With *Reduce animations* on, the animation does not play.

## 25. Pane animations and notifications (snackbars)

**Panes.** Showing, hiding or collapsing a pane (from the title bar *View* menu, or with the shortcut) animates its width. Text in the other columns does not rewrap during the animation: the layout is stable and the incoming pane fades into place. With *Reduce animations* (section 23) or the system preference on, the layout changes at once and the incoming pane only fades, without movement.

**Side conversation.** Opening the side conversation from the command palette (*Side conversation*) splits the chat area in two; the split follows the same animation rule as panes. Details in [section 19](#19-read-only-side-conversations).

**Notifications (snackbars).**
- Success messages appear at the bottom right and close by themselves after 4 seconds. A click on the card closes them at once.
- Error messages stay visible until you close them with the ✕ (they are also announced to screen readers).
- With *Reduce animations* on, the notification does not slide: it fades in.

## 26. Workspace file editor

Opening a file from the **Repository** pane opens the code editor, in a monospace font (Source Code Pro, 13/20 px) for every file type, Markdown included in source mode.

- **Line numbers**: the left column (44 px, in a muted tone) shows a number for every logical line, aligned also when lines wrap. The cursor line has a highlighted number and background.
- **Wrapping**: off for code, on for Markdown and plain text. The *wrap* button in the editor bar changes the choice for the open file.
- **Markdown**: the preview/source button switches between the formatted view and the source text.
- **Go to line**: `Ctrl+G` (`Cmd+G` on macOS) opens *Go to line*; type the number and press Enter.
- **Saving**: `Ctrl+S` (`Cmd+S` on macOS) saves the file. A file with unsaved changes shows a `●` next to its name and a filled *Save* button; with a clean file *Save* is a text button.
- **Unsaved changes**: closing the editor or switching session with unsaved changes asks *Save*, *Don't save* or *Cancel*.
- **Add selection to chat**: selecting text and opening the context menu (right-click) shows *Add to chat (file:L10–L24)*. The reference uses the real line range and the full file path in the composer.
- **Folder menu**: right-click a folder in the Repository pane for *New session here*, *Add folder to chat* (inserts `@folder` in the composer) and *Copy path*. File rows also show an *Add to chat* button on hover or focus.

The `Ctrl/Cmd+G` and `Ctrl/Cmd+S` shortcuts work when the cursor is in the editor.

## 27. Settings navigation

In windows at least 900 px wide, **Settings** shows a navigation column on the left with three groups: **General** (Appearance, Terminal, Updates), **Pi** (Pi CLI, Packages, Agents) and **System** (Daemon, Diagnostics, Remote access; privacy is under Diagnostics). In narrower windows the navigation becomes a scrollable row of tabs. The ↑/↓ arrows move the selection between sections, Esc closes Settings, and the header shows the state of the active session (for example *Running*) even while you are in Settings.

### Other Settings changes

- **Appearance → Theme**: a single control with three choices, **System**, **Light** and **Dark**. With *System*, both the *Default dark theme* and *Default light theme* pickers appear; with *Light* or *Dark*, only the picker for that mode appears. The info block that repeated the active theme was removed. *Nerd stats* is now called **Technical stats**.
- **Privacy** is no longer a navigation entry: the privacy text and the zero-telemetry note are in the **Diagnostics** section.
- **Terminal**: the list of native terminal apps is disabled until you choose *Native OS terminal*.
- **Daemon → Restart daemon**: the text under the button says that *running sessions will reconnect*. If an agent is running, PiFrame asks for confirmation before restarting.
- **Pi CLI**: the recommended command (`pi update`) is marked *Recommended*; every *Run* button is outlined. In wide windows the command output is in a column on the right; in narrow windows, starting a command scrolls the output into view.

## 28. Welcome screen and new session

When no session is open, the welcome screen is a place to pick work back up.

- **Resume work**: on the left, the description, **New session** (primary button) and **Browse sessions**. On the right, up to 8 recent sessions grouped by repository, as selectable rows. With a physical keyboard, ↑/↓ move and Enter opens the session. On phones and tablets (without a physical keyboard) the "Ctrl / Cmd + K" hint does not appear. Below 960 px of width the sessions move below the buttons; below 640 px the title is smaller.
- **First launch**: on the first start, the title, description and buttons appear in sequence (300 ms each, staggered by 100 ms, with a slight rise). With "Reduce animations" only a fade appears. The flag is saved in `~/.piframe/app_first_run.json` (key `introPlayed`), separate from `first_run.json`, which is about installing Pi; later launches do not repeat the animation.
- **New session**: opens a 480 px dialog with the "Folder path…" field (prefilled with the active session's folder, if any), a button to pick a folder from the computer and up to 5 recent folders to select with a click. The path is checked 300 ms after the last edit:
  - "Folder not found": the path does not exist and **Create** stays disabled;
  - "Git repository detected · <branch>": the folder is a Git repository, and the branch is read from `HEAD` (on a detached HEAD only "Git repository detected" appears);
  - "Folder found": an existing folder that is not a Git repository.
  Enter creates the session when the path is valid, Esc closes the dialog. The welcome button stays still until you press **Create**.
- In the browser the path cannot be checked on the computer: the field accepts any non-empty path and shows the reminder about the local path. On the computer the check uses the app's file system: if the app and the daemon run on different machines, the result is about the app's machine.

## 29. Composer during a run, review and empty chat

**Status row.** While Pi answers, a 28 px row appears above the input field with the indicator *The agent is answering…*, the elapsed time and the **Stop** button. The row appears and disappears without moving the message being scrolled. With reduced motion the indicator is a static icon.

**Keys during a run.**
- `Esc` stops the run.
- With **Send with Enter** on, `Enter` applies a *steer* (redirects the agent without stopping it); `Shift+Enter` inserts a new line.
- With **Send with Enter** off, `Ctrl+Enter` (or `Cmd+Enter`) applies the steer; `Enter` inserts a new line.
- To send a message after the current answer, use **Follow-up: queue** to queue it.

**Review button.** When Pi changes files, the composer shows **Review changes (n)** with the number of changed files. Pressing it opens the review of the session's changes; pressing it again closes it. Without changes the button is hidden; it appears as soon as Pi changes a file.

**Empty chat.** A session without messages shows the name of the working folder, the Git branch (if any) and three hints: `/` for commands, `@` to attach a file, `Ctrl/Cmd+K` for the command palette. The input field takes focus as soon as it appears, so you can type at once.

## 30. Desktop taskbar and dock indicators

When an agent is operating in any monitored or active session:
- **Windows**: the taskbar button displays the animated green progress marquee (`TBPF_INDETERMINATE`) via direct Win32 COM (`ITaskbarList3`) while an agent is actively working, and switches to a solid progress indicator (`TBPF_NORMAL`) when the agent completes its final answer while PiFrame is not focused.
- **macOS**: the dock tile displays an active progress indicator and `⋯` badge while the agent is working, and displays an unread notification badge dot (`•`) when an answer finishes while the app is in the background.
- **Linux & Window Title**: the window title reflects the state with `● PiFrame` during execution and `• PiFrame` when unread.
- Focusing or opening PiFrame immediately clears the unread indicator and dock badge back to normal (`idle`).

## 31. Post-update changelog popup

When PiFrame is updated to a new release, the first time the app is opened after the update, a modal dialog automatically appears showing the release highlights:
- **Filtered changelog:** displays only new user-facing features (`feat`) and bug fixes (`fix`), omitting internal chores, documentation, and CI/test commits.
- **Scope badges:** highlights the affected area (e.g. `settings`, `chat`, `git`, `workspace`, `agentd`) and cleans commit links.
- **Per-release persistence:** remembers the last seen version in `~/.piframe/changelog_state.json` so the popup appears only once per release and never on brand new installs.
- **On-demand review:** you can also review the current release notes at any time from **Settings → Updates → Release notes** (`Note di rilascio`).
- **Always complete:** the popup's changelog (`apps/pi_frame/assets/CHANGELOG.md`) is generated from the root `CHANGELOG.md` and not committed. `pnpm run setup` (and `pnpm run sync:changelog`, `run:app`, `run:app:dev`, the packaging scripts and the release workflow) generate it before Flutter runs or builds, and `pnpm run check:version` fails, without writing, when it is missing or stale, so a release can no longer ship without its own entry.
