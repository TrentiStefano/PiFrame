# Troubleshooting

Known problems and quirks you can hit while using PiFrame, grouped by platform, each with what you can do about it. Terms such as daemon, Pi worker or compaction are defined in the [glossary](../GLOSSARY.md); what each feature does is in the [user guide](user-guide.md). Problems with building PiFrame or running its checks are in the [verification guide](pr-verification.md#build-and-release-problems).

- [Windows](#windows)
- [macOS](#macos)
- [Linux](#linux)
- [All platforms](#all-platforms)

---

## Windows

### Blank or white window at startup

**What you see:** the PiFrame window opens and the process runs normally, but the window stays completely white or black.

**Why:** Flutter draws through Direct3D 11. With virtual display drivers (`USB Mobile Monitor Virtual Display`, `IddSampleDriver`, Spacedesk, Duet Display, DisplayLink, RDP or VNC monitors), hybrid GPU setups, or a Desktop Window Manager left in a bad state after a crash or a resume from sleep, Windows never presents the frame. A fresh `flutter create` app shows the same white window, so it is not specific to PiFrame. Upstream reports: [flutter#149709](https://github.com/flutter/flutter/issues/149709), [flutter#160948](https://github.com/flutter/flutter/issues/160948), [flutter#137321](https://github.com/flutter/flutter/issues/137321).

**What to do**, in this order:

1. Restart Windows fully (**Start → Restart**, not shut down and power on, which uses Fast Startup).
2. Disable virtual displays: open **Device Manager**, expand **Display adapters**, right-click the virtual device and choose **Disable device** (or close the phone-mirroring app). Start PiFrame again.
3. On a laptop with two GPUs: open **Settings → System → Display → Graphics**, add `PiFrame.exe` (by default in `%LOCALAPPDATA%\Programs\PiFrame\`), click **Options** and choose **High performance**.
4. If the monitor was off or a DisplayPort monitor was in deep sleep, Windows may have no active display at all (Device Manager shows the monitors as *Unknown*). Wake the monitor, then start PiFrame again. For unattended machines, turn off monitor standby (`powercfg /change monitor-timeout-ac 0`) and the monitor's own deep-sleep setting.

### "MSVCP140.dll was not found" at startup

**What you see:** on a clean Windows install or virtual machine, PiFrame does not start and Windows reports that `MSVCP140.dll`, `VCRUNTIME140.dll` or `VCRUNTIME140_1.dll` was not found.

**Why:** PiFrame needs the Microsoft Visual C++ runtime. The installer ships these DLLs next to `PiFrame.exe`, but a copy that was moved or built by hand may not have them.

**What to do:** reinstall PiFrame with the official installer, or install the runtime yourself:

```powershell
winget install Microsoft.VCRedist.2015+.x64
```

or download it from [aka.ms/vs/17/release/vc_redist.x64.exe](https://aka.ms/vs/17/release/vc_redist.x64.exe).

### WSL session: "Send failed: spawn ...\node.exe ENOENT"

**What you see:** in a session whose workspace is a WSL folder (`\\wsl.localhost\<distro>\...`), sending fails after a period of inactivity, even though `node.exe` exists.

**Why:** the WSL virtual machine had stopped, so Windows could not open the workspace folder for the new Pi worker. PiFrame starts the distro before it starts the worker, and if that still fails the error names the folder (`(cwd: ...)`).

**What to do:** check that the distro still exists and starts (`wsl -d <distro>`), then send again. Update PiFrame if the error still names `node.exe` rather than the folder.

### Daemon unreachable after building PiFrame from source

**What you see:** you built `PiFrame.exe` yourself (for example `flutter build windows --release`); the app cannot connect to the daemon, the sessions list shows `TimeoutException after 0:00:08.000000`, or **Settings → Daemon → Restart daemon** keeps failing.

**Why:** a Flutter build does not rebuild the daemon, and it does not stop a daemon that is already running. When the daemon bundle next to `PiFrame.exe` is older than the app, the app stops it because of the version difference and starts the same old bundle again.

**What to do:**

1. From the repository root, rebuild the daemon first, then the app (the build copies `apps/agentd/dist/pi-agentd.cjs` next to `PiFrame.exe`; copy `node.exe` there too if it is missing):
   ```powershell
   pnpm build:agentd
   ```
2. Let running Pi workers finish, then use **Settings → Daemon → Restart daemon**.
3. If the restart still fails, close PiFrame, end the old daemon (the `pi-agentd` process in Task Manager, or the process id in `~/.piframe/runtime/daemon.json`), and start PiFrame again:
   ```powershell
   Stop-Process -Id (Get-Content "$HOME\.piframe\runtime\daemon.json" | ConvertFrom-Json).pid
   ```

---

## macOS

### "Apple cannot check it for malicious software"

**What you see:** opening `PiFrame.app` shows a Gatekeeper warning, or the app does not open.

**Why:** PiFrame is not signed with a paid Apple Developer ID nor notarized by Apple; the release build has only the ad hoc signature that Apple Silicon requires. macOS blocks every downloaded app like that until you allow it.

**What to do:** either

- open `PiFrame.app`, close the warning, then open **System Settings → Privacy & Security**, scroll to **Security**, click **Open Anyway** next to the PiFrame message and confirm with your password or Touch ID; or
- clear the quarantine attribute once in Terminal:
  ```bash
  xattr -cr /Applications/PiFrame.app
  ```

After that, PiFrame opens with a normal double-click.

### Pi reported as not installed, or "pi: command not found [code 127]"

**What you see:** **Settings → Pi CLI** says Pi is missing, or a command such as `pi update --all` ends with `/bin/sh: pi: command not found`, although `pi` works in Terminal.

**Why:** apps started from Finder, the Dock or Spotlight get a minimal `PATH`. PiFrame adds `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/share/pi-node/current/bin` and the paths of your login shell, so a `pi` installed elsewhere may not be found.

**What to do:** install Pi with the official script or Homebrew, or make your login shell's `PATH` (in `~/.zprofile`) include the folder that holds `pi`. Then quit and reopen PiFrame.

---

## Linux

### The `.deb` package does not start: WebKitGTK or libnotify missing

**What you see:** after installing PiFrame from the `.deb`, it does not start and reports a missing `libwebkit2gtk-4.1` or `libnotify` library.

**Why:** the package declares `libwebkit2gtk-4.1-0` and `libnotify4` as dependencies, but `dpkg -i` does not install dependencies.

**What to do:** install the package with `apt`, which resolves them:

```bash
sudo apt install ./PiFrame-<version>-linux-amd64.deb
```

---

## All platforms

### A problem is still there after updating PiFrame

**Why:** the daemon keeps running in the background with the code it started with. Updating or rebuilding the app does not restart it, and many fixes are in the daemon.

**What to do:** let running Pi workers finish, then use **Settings → Daemon → Restart daemon**. Running sessions reconnect; PiFrame asks first if an agent is running. Updated Pi extensions load the next time a Pi worker starts.

### An error shows only a short message

**What you see:** Git, the file list, the package list or another screen says something like "Operation failed" or "Could not load packages".

**What to do:** open the error box and press **Details**: the original technical text is selectable and can be copied into a bug report. **Retry** repeats the operation when it can be retried. Messages from Pi or the provider (for example a rate limit or an unavailable model) are shown as they arrive. If a send fails, the message keeps its text and attachments: use **Retry send**, or double-click it to edit it in the composer.

### The phone shows "The local daemon is running" instead of PiFrame

**What you see:** with remote access, the phone opens a static *PiFrame Daemon* page instead of the app.

**Why:** the daemon could not find the web build of the app. The installers include it; a source build may not.

**What to do:** use an installed PiFrame, or build the web app from the repository and copy the files from `apps/pi_frame/build/web` to `~/.piframe/web/`:

```bash
cd apps/pi_frame
flutter build web --no-web-resources-cdn
```

### The web app on the phone does not work as expected

- **"Pair the device again"**: create a new pairing QR code in **Settings → Remote access**. A web app added to the iOS Home Screen has storage separate from Safari, so pair it from there too.
- **"Computer not reachable"**: check that PiFrame is open on the computer, remote access is on, and Tailscale is connected on the phone.
- **Screenshots or files from the phone do not reach the agent**: the device needs control mode (**Settings → Remote access**); in view mode a notice says it is read-only. Each file can be up to 50 MB.
- **Blank background after an update, zoomed or cut-off interface while typing**: close and reopen the web app (or the Home Screen icon) so it loads the current version.
- **No integrated browser**: the browser pane exists only in the desktop app; on a phone or remote browser, open links in the device's own browser.

See [PiFrame on your phone](user-guide.md#14-piframe-on-your-phone-remote-access) for how the web app behaves.

### An extension update fails with `EBADPLATFORM`

**What you see:** on the **Packages** page an extension update is not offered, with a platform-incompatibility reason.

**Why:** a dependency the extension requires is not published for your operating system. For example `@hypabolic/pi-hypa@1.2.0` needs a package available only on macOS and Linux. PiFrame checks the install with a dry run first and does not offer a version that cannot install.

**What to do:** keep the current version, or install an older compatible version and keep it with **Pin version** (for example `0.1.15` of that extension on Windows). PiFrame never pins or changes a package source by itself.

### Subagents fail with `ERR_MODULE_NOT_FOUND ... subagent-context-limit.mjs` after removing PiFrame

**What you see:** after uninstalling PiFrame or deleting `~/.piframe`, subagents started from Pi in a terminal fail with `Cannot find module '.../.piframe/runtime/subagent-context-limit.mjs'`.

**Why:** a subagent context limit set in PiFrame adds that file to `subagents.agentOverrides.<name>.subagentOnlyExtensions` in `~/.pi/agent/settings.json`.

**What to do:**

- Before uninstalling, reset the subagent context limits in **Settings → Agents** and save.
- If PiFrame is already gone, open `~/.pi/agent/settings.json` and remove the `subagent-context-limit.mjs` entry from each agent's `subagentOnlyExtensions` (or the whole property if it holds nothing else).
- Starting PiFrame again also restores the file while a setting still refers to it.

### A model override in Settings → Agents has no effect

**What you see:** a subagent still runs with its old model or thinking level, or **Context** shows `n/a`.

**Why:** with `@tintinweb/pi-subagents`, the agent file's own `model:` and `thinking:` lines decide. PiFrame writes your choice into the file of a user agent (`~/.pi/agent/agents/*.md`, with a `.piframe-backup` copy); package and project agents are read-only. That package has no per-agent context limit, hence `n/a`.

**What to do:** overrides saved by an older PiFrame are listed in a warning on the page: pick the value again to write it to the agent file, or press **Reset** to clear the old entry. **Reset** always restores the line as it was before PiFrame first changed it, even if you edited the file by hand since.

### Copilot models missing, or the context limit is not applied

- **A Copilot model is missing**: PiFrame shows only models your GitHub account and organization allow. Check the entitlement on GitHub. If a verification notice appears, check the network and that you are signed in with Pi; successful checks are cached for at most one minute.
- **The maximum slider is hidden**: choose **Custom** in the context size first. Custom moves in 50k steps; the margin in 0.5% steps, from 0.5% to 25%. A 5% margin compacts at 95% of the chosen maximum.
- **"Pi did not apply the context limit"**: update Pi and restart the Pi worker (or the daemon).
- **Compaction does not start**: check that automatic compaction is on in Pi's settings, and change the limit only while no turn is running. Switching model resets the context limit to the new model's full window.
- **Compaction fails or frees too little**: raise the limit or reduce what Pi keeps in context. A context limit cannot cap your bill: single outputs and the summary request still use tokens.

### Messages wait while Pi is compacting

A message sent during compaction is sent as a steer or held until the compaction ends (at most 10 minutes), because Pi refuses new prompts while it compacts. Wait for "Compacting…" to finish; until the next answer arrives the context chip shows Pi's estimate or "post-compaction".

### Some Pi slash commands show a message instead of running

The `/` menu lists all of Pi's built-in commands. Most run in PiFrame (`/settings`, `/model`, `/tree`, `/thinking`, `/new`, `/compact`, `/reload`, `/copy`, `/name`, `/session`, `/fork`, `/clone`, `/resume`, `/quit`); the others need Pi's terminal interface, so PiFrame explains that instead of sending them to the model. Run those in Pi in a terminal.

### Subagent cost shows `N/A` or zero

PiFrame shows only costs that Pi recorded, never estimates. A provider or model without pricing reports zero, and missing data stays `N/A`; the attributed total is then marked as partial. The session cost from Pi and the costs of subagents are shown separately because Pi may already include the latter.

### A question preview is cut off

Questions from `rpiv-ask-user-question` send at most the first 600 characters of each preview, so PiFrame cannot show more. Change the selected option with the mouse or the up/down arrows to see its preview.

### Session titles or chips appear late or out of view

- With many sessions, the first list comes from the daemon's cache and is completed in the background: a session may show its id or an older title for a moment.
- In a narrow chat pane, the chips beside the session status scroll horizontally: scroll the header to see the cost chip.
