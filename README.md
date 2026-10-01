# Pi-Crust 🥧

> **Modern, resilient, decoupled GUI (Windows, macOS, and Web) for [`pi-coding-agent`](https://github.com/earendil-works/pi), inspired by OpenAI Codex and GitHub Copilot app interfaces.**

---

## 🌟 Overview

**Pi-Crust** is a high-performance desktop and web graphical user interface for `pi-coding-agent`. Unlike terminal-locked or web-only wrappers, Pi-Crust is built on a **resilient three-tier decoupled architecture**:
- The GUI can be closed, reloaded, or crash without terminating the running Pi agent.
- A persistent local daemon keeps tasks running, journals every event with monotonic sequence numbers, and allows seamless reattachment and replay upon GUI reconnect.
- Authoritative session history remains strictly owned by Pi (`~/.pi/agent/sessions/`), guaranteeing 100% compatibility with the official Pi CLI.
- Built with **strictly zero remote telemetry** (Decision D16) and a loopback-only security boundary.

---

## 🏗 Architecture

```text
┌───────────────────────────────────────────────────────────────┐
│  Pi-Crust (Flutter Desktop & Web)                             │
│  Windows · macOS · Web (Chrome / Edge)                        │
│  ── Presentation + Session Projection + Command Dispatcher    │
└──────────────────────────┬────────────────────────────────────┘
                           │  PCP/1 (Pi-Crust Protocol, JSON over WebSocket)
                           │  127.0.0.1 · Bearer token · Strict Origin check
                           ▼
┌───────────────────────────────────────────────────────────────┐
│  pi-agentd (TypeScript / Node.js persistent daemon)          │
│                                                               │
│  ConnectionManager   SessionRegistry    EventJournal (Replay) │
│  CommandDispatcher   WorkspaceService   UiRequestBroker       │
│  PiDiscovery         WorkerSupervisor   SnapshotBuilder       │
│                          │                                    │
│                          ▼  PiTransport (interface)           │
│                     StdioPiTransport                          │
└──────────────────────────┬────────────────────────────────────┘
                           │  JSONL strict LF over stdin/stdout
              ┌────────────┼────────────┬────────────┐
              ▼            ▼            ▼            ▼
        pi --mode rpc  pi --mode rpc  pi --mode rpc  …
         (Session A)    (Session B)    (Session C)
              │
              ▼
        ~/.pi/agent/sessions/--<path>--/<ts>_<uuid>.jsonl
        (Source of truth of history — owned exclusively by Pi)
```

### Decoupling Rules
1. **Pi-Crust (Flutter):** Manages user experience, state reduction, layout, themes, and commands. Knows nothing about child processes, stdio streams, or JSONL files.
2. **pi-agentd (Daemon):** Manages process lifecycles, Pi RPC communication, session registries, event replay, git status, and authentication. Knows nothing about widgets or UI layout.
3. **Pi (`pi-coding-agent`):** Manages agent intelligence, tools, models, extensions, and session persistence. Completely unaware that Pi-Crust exists.

---

## ✨ Features

- **🛡 Disconnect-Safe & Background Execution:** Close the window anytime while Pi is working on large refactors. The daemon buffers the stream into a monotonic event journal. Reopen the GUI, and the session catches up instantly without gaps or duplicate events.
- **💬 Rich Streaming Transcript:**
  - Token-level text streaming with sub-100ms latency.
  - Collapsible **Thinking / Reasoning** blocks with live step streaming.
  - Syntax-highlighted code blocks with language badge and one-click copy.
  - Inline unified **Diff Viewer** for file modifications.
  - Interactive **Tool Cards** showing tool execution status, parameters, output, and execution duration.
- **🌲 Multi-Session Management & Visual Branching:**
  - Fast search and filtering across sessions (Active, Repository, All).
  - Visual **Session Tree** dialog inspecting turns, forks, and branches.
  - **Fork ("Riparti da qui")** from any turn or user prompt, and session cloning.
- **🔍 Workspace & Git Insights:**
  - Real-time Git status indicator (branch, clean/dirty state, line additions and deletions).
  - Modified files list with status badges (`M`, `A`, `D`, `?`).
  - Click-to-inspect full file diff modal dialog.
- **🎨 Extensible JSON Theme Engine (`pi_crust_theme`):**
  - Ships with bundled high-contrast Dark and Light themes (`crust-dark`, `crust-light`).
  - Supports custom user themes placed in `~/.pi-crust/themes/` with inheritance (`extends`), cyclic dependency validation, and live hot-reload.
  - Strict WCAG AA contrast compliance and zero hard-coded widget colors.
- **🧩 Interactive Extension Dialogs:**
  - Supports Pi extension UI dialogs (`select`, `confirm`, `input`, `editor`).
  - Server-side **Claim/Lease Broker** prevents multiple open GUI windows from submitting conflicting responses to the same prompt.
- **🔒 Privacy & Security First:**
  - Strictly bound to loopback `127.0.0.1`.
  - 256-bit cryptographically random authentication tokens with constant-time verification.
  - Strict HTTP Origin allowlist and Content Security Policy (CSP).
  - **Zero Remote Telemetry:** No analytics SDKs, no external tracking, no outbound network requests outside loopback. Diagnostic bundles redact all secrets before export.

---

## 📋 Prerequisites

Before building or running Pi-Crust, ensure the following are installed on your machine:

1. **Flutter SDK:** Flutter `3.47.2` or later with Dart `>= 3.13.2` (the constraint in `pubspec.yaml`).
2. **Node.js & pnpm:** Node.js `>= 22.19.0` and `pnpm >= 9.0.0`.
3. **Pi CLI:**
   - Install `@earendil-works/pi-coding-agent` globally (real CLI integration verified with `v0.99.2`), or
   - Use the included **`fake-pi`** tool for local development and testing without requiring LLM API keys.
4. **For Windows Desktop (.exe):**
   - **Visual Studio 2022+** with the **"Desktop development with C++"** workload installed (standard requirement for Flutter Windows development).

---

## 🚀 Quick Start (Development Mode)

### 1. Install Dependencies & Build Packages
Clone the repository and install all monorepo dependencies:
```bash
# Clone repository
git clone https://github.com/TrentiStefano/pi-crust.git
cd pi-crust

# Install Node dependencies
pnpm install

# Build TypeScript protocol packages
pnpm build:all
```

### 2. Start the Daemon (`pi-agentd`)
In a terminal, start the daemon:
```bash
# Option A: Standard mode (uses installed 'pi' CLI)
pnpm run:daemon

# Option B: Development mode using fake-pi (no LLM key needed)
# On Windows PowerShell:
$env:PI_CRUST_PI_PATH = "$PWD/tools/fake-pi/dist/index.js"; pnpm run:daemon

# On Linux/macOS:
PI_CRUST_PI_PATH="$PWD/tools/fake-pi/dist/index.js" pnpm run:daemon
```
The daemon will initialize `~/.pi-crust/runtime/`, write `daemon.json` and `daemon.token`, and start listening on `127.0.0.1`.

### 3. Launch the Flutter GUI
In a separate terminal, run Pi-Crust:
```bash
cd apps/pi_crust

# Run as Windows Desktop app:
flutter run -d windows

# Build the Web application with local renderer assets:
flutter build web --no-web-resources-cdn
```

For Web, serve the build from the daemon's own origin. From the repository root, start the daemon with:
```powershell
$env:PI_CRUST_WEB_DIR = "$PWD/apps/pi_crust/build/web"
pnpm run:daemon
```
On Linux/macOS, use `PI_CRUST_WEB_DIR="$PWD/apps/pi_crust/build/web" pnpm run:daemon`.
Open `http://127.0.0.1:<port>/`, using the port printed by the daemon. A separate `flutter run -d chrome` server cannot discover native runtime files.

### Existing terminal sessions
The sidebar indexes Pi session files and hides sessions whose project path is inside the OS temporary directory.
Closed sessions open directly in Pi-Crust and continue in the original Pi session file.
Pi does not expose the exact session selected by an already-running terminal process. Pi-Crust detects explicit session arguments and treats other Pi processes in the same project as ambiguous.
Ambiguous sessions stay read-only until you confirm that the terminal is not using that session. Use **Duplica e continua** to avoid shared writes.
The **Gestite** filter shows daemon-managed sessions. It does not list live terminal processes.
The model picker applies Pi's global `enabledModels` setting and Pi's authenticated-model list.
Set `PI_CODING_AGENT_SESSION_DIR` on the daemon to index a custom session directory.

---

## 📦 Building the Windows Executable (`.exe`)

You can compile a standalone, high-performance Windows release executable in two simple steps:

### Step 1: Bundle the Daemon Sidecar
Bundle the daemon into a single self-contained CommonJS file:
```bash
pnpm --filter @pi-crust/agentd build:bundle
```
*(Optionally, you can create a Node Single Executable Application via `pnpm --filter @pi-crust/agentd build:sea`)*.

### Step 2: Build the Flutter Windows Release
Compile the Flutter desktop application:
```bash
cd apps/pi_crust
flutter build windows --release
```

### Step 3: Run and Test the Executable
Once compilation completes, the release output will be located in:
```text
apps/pi_crust/build/windows/x64/runner/Release/
├── pi_crust.exe           # The main executable
├── pi-agentd.cjs          # Daemon sidecar copied by the Windows build
├── flutter_windows.dll    # Flutter engine runtime
└── data/                  # Assets, fonts, and bundled themes
```

#### How to test it:
1. **With daemon running:** If `pi-agentd` is already running (`pnpm run:daemon`), simply double-click `pi_crust.exe`. The application automatically discovers the active daemon via `~/.pi-crust/runtime/daemon.json` and authenticates.
2. **Autonomous launch:** If no daemon is running, `pi_crust.exe` checks for adjacent `pi-agentd.exe`, `pi-agentd.cjs`, or `dist/pi-agentd.cjs`. It also accepts `PI_CRUST_DAEMON_BIN`.
3. **Node requirement:** The `.cjs` sidecar requires `node` on PATH. A Node SEA executable does not require a separate Node installation.
4. **Reconnect:** Desktop reconnects re-read the daemon endpoint. Commands with uncertain outcomes are not replayed after the daemon token changes.

---

## 🧪 Testing & Verification

Pi-Crust maintains a rigorous automated testing matrix across all packages:

```bash
# Run all unit, contract, security, and Flutter tests:
pnpm test

# Run End-to-End and Fault Injection test suites:
pnpm test:e2e

# Exercise the installed real Pi CLI with an isolated, loopback mock model:
# No real LLM calls or changes to existing Pi sessions.
pnpm smoke:real-pi

# Run Flutter static analysis:
cd apps/pi_crust
flutter analyze
```

### Test Suites Breakdown:
- **`apps/agentd`:** Unit & integration tests (JSONL framer, EventJournal, Replay matrix, UiRequestBroker, Git client, Security review, D16 telemetry ban).
- **`apps/pi_crust`:** Widget & domain tests (Adaptive composer, Rich transcript, Thinking block, Tool card, Context panel, Sessions sidebar, Diagnostics).
- **`packages/pi_crust_protocol`:** 4 contract serialization & forward compatibility tests.
- **`packages/pi_crust_theme`:** 7 theme parsing, inheritance, and cycle detection tests.
- **`test/e2e`:** 4 end-to-end integration tests, including:
  - **M1 Proof of Architecture:** Disconnecting GUI mid-stream does not interrupt Pi; reconnected client catches up cleanly.
  - **Fault Injection:** Duplicate frame delivery, corrupted frames, and abrupt WebSocket drops.

---

## 📂 Repository Structure

```text
pi-crust/
├── apps/
│   ├── pi_crust/                 # Flutter application (Windows, macOS, Web)
│   │   ├── lib/                  # App shell, state reducers, UI features
│   │   ├── assets/themes/        # Bundled official themes (crust-dark, crust-light)
│   │   └── test/                 # Widget, smoke, and lint tests
│   └── agentd/                   # Node.js / TypeScript persistent daemon
│       ├── src/server/           # HTTP/WS server, token auth, static SPA server
│       ├── src/sessions/         # Session registry, supervisor, indexer
│       ├── src/journal/          # Monotonic event journal, buffer, snapshot
│       ├── src/workspace/        # WorkspaceService, read-only Git client
│       └── src/ui/               # UiRequestBroker (claim/lease management)
├── packages/
│   ├── pcp-spec/                 # Source of truth: PCP/1 protocol specification & JSON Schemas
│   ├── pcp-ts/                   # Generated TypeScript types & validators
│   ├── pi_crust_protocol/        # Generated Dart types & codec for Flutter
│   └── pi_crust_theme/           # Dart theme engine with JSON inheritance & hot-reload
├── tools/
│   ├── fake-pi/                  # Scriptable mock Pi RPC server for testing
│   ├── fault-proxy/              # WebSocket proxy for network fault injection
│   └── codegen/                  # JSON Schema -> TypeScript & Dart code generator
├── test/e2e/                     # Cross-component end-to-end test scenarios
├── docs/                         # Architecture, Security baseline, ADRs, Installation guides
└── themes/                       # Source theme definitions and JSON schemas
```

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.