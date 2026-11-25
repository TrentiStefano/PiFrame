# Installing, updating and operating PiFrame

This guide covers what PiFrame installs, how to install and update it, how the daemon runs and how to remove PiFrame safely. What the app does, feature by feature, is in the [user guide](user-guide.md); fixes for known problems are in the [troubleshooting guide](troubleshooting.md).

---

## 1. What gets installed

PiFrame has two parts, plus the Pi coding agent it drives:
1. **PiFrame app**: the Flutter app for Windows, macOS and Linux. A web build is served by the daemon for local and remote access.
2. **Daemon** (executable `pi-agentd`): a Node.js process shipped in the installers together with the Node runtime. It starts one Pi worker (`pi --mode rpc`) per session, keeps each session's journal and serves the app over PCP, the PiFrame Communication Protocol ([ADR 0014](adr/0014-daemon-distribution-sidecar.md)).
3. **Pi**: your own Pi installation (`v0.85.0+`), which stays external in `~/.pi/`. PiFrame never moves or overwrites Pi's session files; it changes files in `~/.pi/` only when you ask it to from the app (for example deleting a session, toggling an MCP server or editing agent settings).

---

## 2. System requirements

- **Supported operating systems**:
  - macOS 12+ (Apple Silicon `arm64` and Intel `x64`)
  - Windows 10/11 (`x64`)
  - Linux x64 (Debian/Ubuntu distributions with GTK 3)
- **Node.js**: the installers include the Node runtime and the daemon; you do not need to install Node separately. Building from source needs Node.js ≥ 22.19.0.
- **Pi coding agent** (not included in the installer): minimum version **v0.85.0** ([ADR 0015](adr/0015-minimum-supported-pi-version.md)), installed and on `PATH`. You can install it from PiFrame's first-run screen or with the official commands:
    - macOS / Linux: `curl -fsSL https://pi.dev/install.sh | sh`
    - Windows: `powershell -c "irm https://pi.dev/install.ps1 | iex"`
    - With npm: `npm install -g @earendil-works/pi-coding-agent`

---

## 3. Installation

Download the latest installer from the [GitHub Releases page](https://github.com/TrentiStefano/piframe/releases/latest). Each release has installers for Windows, macOS (Intel and Apple silicon) and Linux x64.

### macOS
1. Open the `.dmg` file and drag `PiFrame.app` into `/Applications`. The DMG window includes a step-by-step guide, `README - How to open.txt`, with an Italian copy next to it.
2. On first launch, PiFrame starts the daemon with the Node runtime bundled in the package.
3. **Gatekeeper warning:**
   - Apple requires a paid **Apple Developer Program** membership to issue *Developer ID Application* certificates and to notarize apps, so PiFrame's free releases are not notarized.
   - The app is signed ad hoc, so it runs correctly on Apple Silicon (`arm64`) and Intel (`x64`).
   - When you download the app with a browser, macOS adds the `com.apple.quarantine` attribute. To open it the first time, either:
     - **From System Settings (macOS 14 Sonoma / 15 Sequoia):** open PiFrame (Gatekeeper shows its message), go to **System Settings → Privacy & Security**, scroll to **Security** and click **Open Anyway**, then confirm with your password or Touch ID.
     - **From Terminal:**
       ```bash
       xattr -cr /Applications/PiFrame.app
       ```
       This removes the quarantine flags from the PiFrame bundle, so it opens with a double-click.

### Windows
1. Run `PiFrame-Setup-…-windows-x64.exe`.
2. The installer adds Start menu shortcuts; the desktop icon is optional.
3. PiFrame bundles the daemon with its own Node runtime and the Microsoft Visual C++ runtime (`msvcp140.dll`, `vcruntime140.dll` and so on) next to the app, so it also works on clean Windows installs. The installer is not signed, so SmartScreen may show a warning.

> [!TIP]
> **White window or frozen rendering?** With virtual display drivers (for example `USB Mobile Monitor`, `IddSampleDriver`) or multi-GPU setups, see the [troubleshooting guide](troubleshooting.md) for quick fixes.

### Linux (Debian / Ubuntu)
Install the downloaded `.deb` package:

```bash
sudo apt install ./PiFrame-…-linux-amd64.deb
```

The package adds PiFrame to the applications menu and includes the daemon and the Node runtime.

### Local web (`http://127.0.0.1:<port>/`)
1. The daemon also serves the web build of the PiFrame app.
2. When you open `http://127.0.0.1:<port>/` in a local browser, the daemon sets an `HttpOnly; SameSite=Strict` cookie with the authentication token, so access works at once without manual setup ([ADR 0013](adr/0013-local-web-hosting.md)).

### From source
To build and run PiFrame from a clone of the repository, follow [Build from source](../README.md#build-from-source) in the README. A source build does not stop a daemon that is already running: after rebuilding the daemon, use **Settings → Daemon → Restart daemon** to load it (see [Build and release problems](pr-verification.md#build-and-release-problems) in the verification guide).

---

## 4. Running the daemon

The daemon starts on demand and is not a system service ([ADR 0008](adr/0008-daemon-lifecycle-on-demand.md)).

- **On-demand startup**: the app checks `GET http://127.0.0.1:<port>/api/health`; if the daemon is not running, it starts it in the background with the bundled Node runtime. Closing the app window does not stop the daemon, so running agents keep working.
- **Runtime files** in `~/.piframe/runtime/`:
  - `daemon.json`: the port and the process id.
  - `daemon.lock`: prevents a second daemon from starting.
  - `daemon.token`: the 256-bit authentication token, readable only by you (permissions 0600).
- **Log**: `~/.piframe/runtime/daemon.log`, rotated across 5 files of 5 MB each.
- **Pi worker idle timeout** ([ADR 0009](adr/0009-worker-idle-timeout.md)): a Pi worker with nothing to do is stopped after 30 minutes by default (adjustable in Settings). A Pi worker that is working, retrying, compacting or waiting for your answer is never stopped for inactivity.
- **Restart**: **Settings → Daemon → Restart daemon** restarts it; running sessions reconnect, and PiFrame asks first if an agent is running.

---

## 5. Updates

- **PiFrame**: download and run the installer of the new release. PiFrame checks for updates and tells you when one is available; the first launch after an update shows the [release notes](user-guide.md#13-release-notes-after-an-update).
- **Daemon version**: at startup, the app reads the running daemon's version through `GET /api/health` and compares it with the daemon in the bundle. If they differ, the app tells you and offers a controlled daemon restart, only when no Pi worker is active.
- **Pi and Pi packages**: update Pi from **Settings → Pi CLI** (`pi update`) and its packages from **Settings → Packages** (see [the user guide](user-guide.md#packages-updating-pi-packages)).

---

## 6. Uninstallation

Removing PiFrame is clean and contained:

1. **Reset per-agent context limits** if you set any in **Settings → Agents**: Pi loads them from a file in `~/.piframe`, and removing it while they are set makes Pi fail with `ERR_MODULE_NOT_FOUND` the next time it starts those subagents. If PiFrame is already gone, remove the path from `subagents.agentOverrides.<name>.subagentOnlyExtensions` in `~/.pi/agent/settings.json`.
2. **Remove the app**:
   - macOS: move `PiFrame.app` to the Trash.
   - Windows: uninstall it from Settings → Apps.
   - Linux: `sudo apt remove pi-frame`.
3. **Stop the daemon** (if running): end the `pi-agentd` process from the task manager or with `kill <PID>`.
4. **Delete PiFrame's local data**:
   ```bash
   # macOS / Linux
   rm -rf ~/.piframe

   # Windows PowerShell
   Remove-Item -Recurse -Force "$HOME\.piframe"
   ```

> [!IMPORTANT]
> Uninstalling PiFrame never removes Pi's folder (`~/.pi/`), with its session files, credentials and extensions. Every session stays usable from the Pi terminal after PiFrame is gone.
