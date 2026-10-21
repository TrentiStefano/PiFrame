<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/design-evidence/icons/piframe-dark-1024.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/design-evidence/icons/piframe-light-1024.png">
    <img src="docs/design-evidence/icons/piframe-dark-1024.png" width="132" height="132" alt="PiFrame Logo" style="border-radius: 28px; box-shadow: 0 12px 32px rgba(0,0,0,0.25);">
  </picture>
</p>

<h1 align="center">PiFrame</h1>

<p align="center">
  <strong>The modern, resilient Bento GUI for <a href="https://github.com/earendil-works/pi">pi-coding-agent</a>.</strong><br>
  Engineered for developers who demand fluid motion, native desktop speed, and zero lost agent work.
</p>

<p align="center">
  <a href="https://github.com/TrentiStefano/piframe/releases/latest"><img src="https://img.shields.io/github/v/release/TrentiStefano/piframe?style=flat-square&color=ca9ee6" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/platforms-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Web-blue?style=flat-square" alt="Supported Platforms">
  <img src="https://img.shields.io/badge/flutter-3.47%2B-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/typescript-Node.js%2022%2B-3178C6?style=flat-square&logo=typescript&logoColor=white" alt="TypeScript">
  <a href="docs/security.md"><img src="https://img.shields.io/badge/telemetry-strictly%20zero%20(D16)-success?style=flat-square" alt="Zero Telemetry"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License"></a>
</p>

---

## 🎬 A Real Run

Run agents, stream token responses, search and edit repository code with syntax highlighting, steer tasks in-flight, manage Git changes, and run commands inside the integrated terminal without leaving the window:

<p align="center">
  <a href="docs/design-evidence/hero.mp4">
    <img src="docs/design-evidence/hero.gif" alt="A real run in PiFrame: agent working, code editor with syntax highlighting and Ctrl+F, steer queue, integrated terminal, and Git changes review" width="100%" style="border-radius: 12px; border: 1px solid rgba(255,255,255,0.1); box-shadow: 0 16px 40px rgba(0,0,0,0.35);">
  </a>
</p>

<p align="center">
  <sub>A real run: the agent streams reasoning and tokens, tool executes tests, code editor highlights syntax with in-file Ctrl+F match cycling, user modifies the steer queue in-flight, stages Git changes, uses the embedded terminal, and toggles themes. (<a href="docs/design-evidence/hero.mp4">Watch in full quality MP4</a> · <a href="docs/design-evidence/hero.webp">High-definition WebP</a> · <a href="docs/design-evidence/showcase.html">Interactive Web Demo</a>)</sub>
</p>

---

## 🌟 Why PiFrame?

Most AI coding assistants lock you into a monolithic web app or terminal session where closing the tab kills the task. **PiFrame** is built on a **three-tier decoupled architecture**:

1. **🛡 Never Lose Agent Work (Disconnect-Safe):** Close the window, restart your desktop shell, or reload anytime. A background local daemon (`pi-agentd`) keeps the agent running, journals every stream event monotonically, and catches up seamlessly upon GUI reconnect with zero gaps or duplicate events.
2. **📂 100% Native Pi Compatibility:** Authoritative session history remains strictly owned by Pi (`~/.pi/agent/sessions/`). Switch freely between the `pi` terminal CLI and the PiFrame GUI at any moment.
3. **🍱 Bento Triptych Workspace:** Co-visible repository code editor, streaming chat transcript, and interactive Git Changes in a balanced three-compartment view inspired by modern editor ergonomics.
4. **🔒 Local-First & Zero Telemetry (Decision D16):** Strictly bound to `127.0.0.1` with cryptographically random tokens. No third-party analytics, no tracking pixels, no outbound calls beyond your configured model provider.

---

## ✨ Features & Functionality

### 🍱 Bento Triptych Workspace
- **Three co-visible work areas:** Repository file tree & code viewer (Left), Pi chat session (Center), and Git Changes inspector / Review pane (Right).
- **Responsive adaptation:** Seamlessly adjusts from ultra-wide 1440px+ displays down to compact laptop screens and single-column mobile views.
- **Collapsible Panes:** Easily collapse or expand side panels with instant keyboard shortcuts or one-click headers.
- **Companion Tabs:** Effortlessly switch between File Explorer, Review Changes, and the Integrated Terminal.

### 💻 Integrated Terminal with Native OS Integration
- **Direct Hardware Typing:** High-performance integrated terminal emulator embedded directly inside your workspace with hardware-level keyboard typing.
- **Native OS Shells:** Spawns native PowerShell / cmd on Windows, zsh / bash on macOS and Linux.
- **First-Class WSL Support:** Open repositories located inside the Windows Subsystem for Linux (WSL) and run commands directly through an integrated WSL bash terminal.

### 📋 Live Agent ToDo Breakdown
- **Real-Time Task Checklists:** Interactive agent task list panel rendering progress in real time.
- **Synchronized Checkboxes:** Watch tasks auto-check as the agent reaches milestones, or manually interact with task items.

### 🤖 Popdown Subagents Panel
- **Dedicated Subagent Drawer:** Easily monitor parallel or nested subagents spawned during complex tasks.
- **Live Output & Steering:** Expand subagent execution streams, provide directional steer input, or stop unresponsive subagents individually.

### 🔌 MCP Server Management
- **Interactive Server Cards:** Click the Model Context Protocol (MCP) badge to view all configured and active MCP tools and servers.
- **Dynamic Server Toggles:** Enable or disable specific MCP servers with intuitive checkboxes without restarting sessions.

### 🔍 Review Changes Desk & Git Staging
- **50/50 Split Review Pane:** Dedicated side-by-side or unified diff viewing to inspect changes before committing.
- **Comprehensive File Tracking:** Real-time visibility into modified (`M`), added (`A`), deleted (`D`), and untracked (`?`) files.
- **Markdown Live Preview:** Toggle live rendered markdown previews for `.md` files right within the workspace editor.
- **Staging & Revert Controls:** Stage, unstage, or discard changes with one click.

### ⏱ Real-Time Context Usage & Cost Analytics
- **Live Cost & Token Metering:** Accurate real-time session cost and token accumulation tracking mirroring CLI/TUI metrics.
- **Context Window Selector:** Explicitly pick model context bounds for variable-context models (e.g., Luna, Haiku) to optimize performance and billing.

### ✍️ Expanded Composer & Fluid Animations
- **Large Prompt Composer:** Toggle an enlarged input window with rich multiline textarea when composing lengthy prompts.
- **Animated Minimization:** Smooth spring transition automatically minimizes composer input while the agent is generating.
- **In-Queue Steer Editing:** Re-order, modify, or dismiss pending steer instructions while an answer streams.
- **Drag & Drop Attachments:** Drag and drop images or text files directly into chat; view files with inline transcript chips and full-screen lightbox preview.
- **Direct Workspace Navigation:** `Ctrl+Click` on file mentions in the transcript to open the file directly in the OS file explorer.
- **Inline Session Rename:** Double-click or press Enter on the session header to rename sessions on the fly.

### 🌐 Secure Remote Access (Tailscale & Cloudflare)
- **Zero-Config Remote Web Access:** Securely access and control your desktop agent sessions from mobile browsers (iPhone, iPad, Android) or laptops.
- **Tunnels Supported:** Built-in integration for Tailscale and Cloudflare tunnels.
- **Secure Pairing:** Connect with a 6-digit PIN or QR code with automatic credential expiration.
- **View vs. Control Modes:** Fine-grained authorization controls to enforce read-only viewing or explicit authorization for terminal and file modifications.
- **Mobile-Tailored UI:** Specially tuned responsive layout and touch-friendly controls for mobile browsers.

### 🎨 Theme Engine & Customization
- **Official Catppuccin Palettes:** Preloaded with **Frappé** (dark) and **Latte** (light) themes with automatic system theme tracking.
- **VSCode Theme Import:** Import standard VSCode JSON theme files directly into PiFrame.
- **Custom JSON Themes:** Add hot-reloadable themes in `~/.piframe/themes/` with full token inheritance.
- **Instruction File Editor:** Edit repository-specific agent instruction files (`AGENTS.md` / `PI.md`) directly from the session sidebar.

### 🔔 Native Notifications & Auto-Updates
- **Background Completion Alerts:** Receive native OS notifications when the agent finishes long runs or requests human input while the app is unfocused.
- **One-Click Updates:** Check for updates directly inside the Settings view with version change highlights.
- **First-Run Onboarding:** Prompts to install `pi-coding-agent` on first launch if not detected on your system.

---

## 📸 Screenshots

| Catppuccin Frappé (Dark) | Catppuccin Latte (Light) |
| :---: | :---: |
| [![Frappe Dark](docs/design-evidence/bento-triptych-fixture-dark-wide.png)](docs/design-evidence/bento-triptych-fixture-dark-wide.png) | [![Latte Light](docs/design-evidence/bento-triptych-fixture-wide.png)](docs/design-evidence/bento-triptych-fixture-wide.png) |
| *Bento Triptych workspace in dark mode* | *Bento Triptych workspace in light mode* |

| Model & Extension Settings | Compact / Single-Pane Mode |
| :---: | :---: |
| [![Settings](docs/design-evidence/piframe-live-settings-frappe.png)](docs/design-evidence/piframe-live-settings-frappe.png) | [![Compact Mode](docs/design-evidence/bento-triptych-fixture-compact-file.png)](docs/design-evidence/bento-triptych-fixture-compact-file.png) |
| *Model selection, thinking effort, and Pi extensions* | *Compact responsive layout for smaller screens* |

---

## 📥 Download & Installation

Download pre-built binaries from the [**GitHub Releases**](https://github.com/TrentiStefano/piframe/releases/latest) page:

| Operating System | Architecture | Installer / Package | Notes |
| :--- | :--- | :--- | :--- |
| **Windows** | `x64` | [`PiFrame-Setup-…-windows-x64.exe`](https://github.com/TrentiStefano/piframe/releases/latest) | Bundles Node.js & `pi-agentd` |
| **macOS** | `arm64` (Apple Silicon) | [`PiFrame-…-macos-arm64.dmg`](https://github.com/TrentiStefano/piframe/releases/latest) | Drag to `/Applications` |
| **macOS** | `x64` (Intel) | [`PiFrame-…-macos-x64.dmg`](https://github.com/TrentiStefano/piframe/releases/latest) | Drag to `/Applications` |
| **Linux** | `x64` (Debian / Ubuntu) | [`PiFrame-…-linux-amd64.deb`](https://github.com/TrentiStefano/piframe/releases/latest) | `sudo apt install ./PiFrame-…deb` |

> [!NOTE]
> Installers bundle the GUI app and the runtime daemon (`pi-agentd`) with an embedded Node.js environment.  
> You only need to ensure the official `pi` CLI is installed on your system.

### Prerequisites

1. **Install Pi CLI** (if not already installed):
   ```bash
   npm install -g @earendil-works/pi-coding-agent
   ```
2. Verify `pi` is accessible from your terminal:
   ```bash
   pi --version
   ```

---

## 🛠 Building from Source

### 1. Clone & Install Dependencies
```bash
# Clone the repository
git clone https://github.com/TrentiStefano/piframe.git
cd piframe

# Install monorepo dependencies
pnpm install

# Build protocol packages and daemon bundle
pnpm build:all
```

### 2. Start the Daemon (`pi-agentd`)
```bash
# Production mode (connects to your real 'pi' CLI)
pnpm run:daemon

# Or local development mode (no LLM API key needed, uses fake-pi)
# On Windows PowerShell:
$env:PI_FRAME_PI_PATH = "$PWD/tools/fake-pi/dist/index.js"; pnpm run:daemon

# On macOS / Linux:
PI_FRAME_PI_PATH="$PWD/tools/fake-pi/dist/index.js" pnpm run:daemon
```

### 3. Run the Flutter App
```bash
cd apps/pi_frame

# Run natively on your desktop platform:
flutter run -d windows   # or 'macos' / 'linux'

# Or build for web (served via daemon origin):
flutter build web --no-web-resources-cdn
```

---

## 🏗 Architecture & Decoupling

```text
┌───────────────────────────────────────────────────────────────┐
│  PiFrame (Flutter Desktop & Web)                              │
│  Windows · macOS · Linux · Web (Chrome / Edge)                │
│  ── Presentation + Session Projection + Command Dispatcher    │
└──────────────────────────┬────────────────────────────────────┘
                           │  PCP/1 (PiFrame Protocol, JSON over WebSocket)
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

| Layer | Responsibility | Isolation Guarantee |
| :--- | :--- | :--- |
| **PiFrame (Flutter)** | UI presentation, Bento triptych layout, state reduction, animations, and theme engine. | Knows **nothing** about child processes, stdio streams, or raw session files. |
| **pi-agentd (Daemon)** | Process supervisor, monotonic event journal, session reconnect replay, Git diff client, and RPC bridge. | Knows **nothing** about Flutter widgets or layout logic. |
| **Pi (`pi-coding-agent`)** | LLM orchestrator, model execution, tool invocation, and file system modifications. | Unaware that PiFrame exists; operates as a standard headless RPC worker. |

---

## 🧪 Testing & Verification

PiFrame enforces 100% test passing across Dart, TypeScript, and protocol specifications:

```bash
# Run all unit, contract, security, and Flutter tests
pnpm test

# Run Flutter tests directly
cd apps/pi_frame
flutter test

# Run End-to-End fault injection test suites
pnpm test:e2e

# Smoke test with real Pi CLI over loopback mock model
pnpm smoke:real-pi
```

---

## 📂 Repository Layout

```text
piframe/
├── apps/
│   ├── pi_frame/                 # Flutter application (Windows, macOS, Linux, Web)
│   │   ├── lib/                  # App shell, Bento workspace, syntax highlighter, composer
│   │   ├── assets/themes/        # Bundled themes (piframe-dark, piframe-light)
│   │   └── test/                 # 87+ widget, stress, layout, and lint tests
│   └── agentd/                   # Persistent Node.js/TypeScript daemon
│       ├── src/server/           # HTTP/WebSocket server, token auth, static SPA host
│       ├── src/sessions/         # Session registry, supervisor, indexer
│       ├── src/journal/          # Monotonic event journal, buffer, snapshot generator
│       ├── src/workspace/        # WorkspaceService, read-only Git client
│       └── src/ui/               # UiRequestBroker (claim/lease broker)
├── packages/
│   ├── pcp-spec/                 # PCP/1 protocol specification & JSON Schemas
│   ├── pcp-ts/                   # Generated TypeScript types & validators
│   ├── pi_frame_protocol/        # Generated Dart types & codec for Flutter
│   └── pi_frame_theme/           # Dart theme engine with JSON inheritance & hot-reload
├── docs/                         # Architecture, Security baseline, ADRs, Installation guides
│   └── design-evidence/         # High-res UI fixtures, showcase videos, and icon assets
├── tools/                        # fake-pi mock server, fault-proxy, codegen scripts
└── test/e2e/                     # Cross-component end-to-end integration tests
```

---

## 📄 License

This project is open-source and available under the [MIT License](LICENSE).