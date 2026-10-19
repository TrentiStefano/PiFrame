# 🎬 Pi-Crust Release Video Automation & Recordly Suite

Pi-Crust features a fully automated, headless promotional video recording and generation suite. Whenever you prepare a new release, redesign the UI, or add new capabilities, running a single command automatically records, auto-zooms, frames, encodes, and exports:

1. **1x 30-Second Hero Promotional Video:** Showcases the core application workflow (Bento Triptych Workspace with live agent streaming, in-file code search with `Ctrl+F`, in-flight steer message queue editing, live Git diff review & 1-click staging, Catppuccin theme toggle, and native OS notifications).
2. **7x Shorter Feature Clips (5–10s each):** Focused, punchy clips demonstrating individual features, ideal for GitHub release notes, social media (X/Twitter, LinkedIn, YouTube Shorts, Discord), and documentation.
3. **Native [Recordly](https://github.com/webadderallorg/Recordly) (`.recordly`) Project Files:** Ready to open in Recordly to add webcam bubble overlays, customize zooms, add voiceovers, or tweak timelines manually.

---

## 🚀 Quick Start

Run the automated generator from the repository root:

```bash
# Generate the 30s hero video + all 7 individual feature clips
pnpm run generate:promos

# Or with Node directly:
node tools/generate-release-promos.cjs
```

### Targeted Commands

```bash
# Generate only the 30-second Hero Walkthrough video
pnpm run generate:promos:hero

# Generate only the 7 individual 5-10s feature clips
pnpm run generate:promos:clips

# Generate a specific feature clip by ID
node tools/generate-release-promos.cjs --clip search
node tools/generate-release-promos.cjs --clip steer
node tools/generate-release-promos.cjs --clip git
node tools/generate-release-promos.cjs --clip theme
```

---

## 📦 Video Catalog & Output Assets

All compiled assets are stored in [`docs/design-evidence/`](file:///c:/Personale/Repos/pi-crust/pi-crust/docs/design-evidence/):

| Clip Name | Target Duration | Formats Generated | Key Features Showcased |
| :--- | :---: | :---: | :--- |
| **⭐ Hero 30s Master Walkthrough** | ~35–40s | `.mp4`, `.webp`, `.gif`, `.recordly` | Full workflow: Bento Workspace, Command Palette (`Ctrl+K`), in-file search, in-flight steer queue editing, thinking stopwatch, tool test runner, context/cost drawer, git diff staging, session tree, theme toggle, and OS toast. |
| **Clip 1: Bento Workspace** | ~4s | `.mp4`, `.webp`, `.gif`, `.recordly` | 3 co-visible areas: Repository & Code, Pi Chat Session, and Git Changes Desk with responsive split. |
| **Clip 2: Command Palette** | ~4.5s | `.mp4`, `.webp`, `.gif`, `.recordly` | Keyboard-first `Ctrl+K` quick action modal with live fuzzy filter across commands. |
| **Clip 3: In-File Code Search** | ~2.5s | `.mp4`, `.webp`, `.gif`, `.recordly` | Syntax highlighting across languages, `Ctrl+F` search overlay, live match cycling (`1 di 2`), and in-file editor. |
| **Clip 4: In-Flight Steer Queue** | ~5.1s | `.mp4`, `.webp`, `.gif`, `.recordly` | Composer directive queuing while agent is streaming, ✏️ Modifica modal, rewording instructions without stopping daemon. |
| **Clip 5: Context & Cost Analytics** | ~4.4s | `.mp4`, `.webp`, `.gif`, `.recordly` | Real-time context usage progress meter (`32k / 200k, 16%`), live token cost counter (`$0.1800`), and model configuration drawer. |
| **Clip 6: Collapsible Reasoning** | ~4.4s | `.mp4`, `.webp`, `.gif`, `.recordly` | Deep thinking block with real-time duration stopwatch, streaming tokens, word count, and collapse toggle. |
| **Clip 7: Tool Execution Timeline** | ~3.6s | `.mp4`, `.webp`, `.gif`, `.recordly` | Expandable `ToolCard` with test runner latency (`4100ms`), verified checkmark (`✓`), and formatted terminal stdout output. |
| **Clip 8: Live Git Changes** | ~4.4s | `.mp4`, `.webp`, `.gif`, `.recordly` | Real-time branch indicator, dirty file badges (`+14 -3`, `+120`), unified diff modal dialog with additions and deletions, and 1-click stage. |
| **Clip 9: Session Tree Branching** | ~3.7s | `.mp4`, `.webp`, `.gif`, `.recordly` | Visual conversation branching tree graph (`SessionTreeDialog`) with active/fork nodes and checkpoints. |
| **Clip 10: Catppuccin Theme Engine** | ~3.4s | `.mp4`, `.webp`, `.gif`, `.recordly` | Seamless hot-reload switch between Catppuccin Frappé (dark) and Catppuccin Latte (light) with zero color glitches. |
| **Clip 11: Disconnect-Safe Daemon** | ~3.4s | `.mp4`, `.webp`, `.gif`, `.recordly` | Resilient local daemon connection (`Pi locale`), 100% offline & zero telemetry badge, and native OS desktop notification toast. |

---

## ✨ Recordly Integration & Visual Aesthetics

The promo generator incorporates the signature motion design and presentation aesthetics of **[Recordly](https://github.com/webadderallorg/Recordly)**:

1. **Dynamic Camera Auto-Zoom & Pan:**
   When an interaction begins (e.g. opening the command palette, searching code with `Ctrl+F`, editing steering directives, inspecting session trees), the camera smoothly zooms in with cubic-bezier easing (`_easeInOutCubic`), highlighting the interaction and easing back out to full view when switching contexts.

2. **Recordly Styled Window & Wallpaper Canvas:**
   The application window is rendered inside a luxurious Recordly desktop canvas:
   - **Canvas Background:** Official Catppuccin Frappé & Macchiato gradient mesh lighting.
   - **Window Frame:** 12px rounded corners, macOS traffic light buttons (🔴 🟡 🟢), and deep multi-layered drop shadow (`box-shadow: 0 28px 75px rgba(0,0,0,0.65)`).
   - **Smooth Mouse Cursor:** Anti-aliased cursor with cubic-bezier motion smoothing and animated click ripple bounce rings.

3. **Native `.recordly` Project Files:**
   In addition to standard video outputs, the generator exports native `.recordly` project manifests to `docs/design-evidence/recordly-projects/`:
   ```
   docs/design-evidence/recordly-projects/
   ├── hero-30s-bento-walkthrough.recordly
   ├── clip-01-bento-workspace.recordly
   ├── clip-02-command-palette.recordly
   ├── clip-03-code-search.recordly
   ├── clip-04-steer-queue.recordly
   ├── clip-05-context-analytics.recordly
   ├── clip-06-reasoning-stream.recordly
   ├── clip-07-tool-timeline.recordly
   ├── clip-08-git-staging.recordly
   ├── clip-09-session-tree.recordly
   ├── clip-10-catppuccin-themes.recordly
   └── clip-11-disconnect-safe.recordly
   ```
   You can drag or open any `.recordly` project inside the Recordly desktop app to fine-tune zooms, add webcam footage, or record voiceovers.

---

## 🛠 Automation in Release Workflow

When creating a new release (or updating the UI):

1. **Verify or update scenarios:**
   If you have introduced new UI components or interactions, you can inspect or extend the Flutter test recording harness in [`apps/pi_crust/test/record_real_app_showcase_test.dart`](file:///c:/Personale/Repos/pi-crust/pi-crust/apps/pi_crust/test/record_real_app_showcase_test.dart). It renders actual Flutter widgets (`AppShell`, `SessionsSidebar`, `RepositoryWorkspace`, `TranscriptView`, `ThinkingBlock`, `Composer`, `GitChangesPane`, `ReviewFileDiffViewer`) inside a Recordly styled window stage and captures frame-by-frame PNGs directly from Flutter's `RenderRepaintBoundary`.

2. **Run the generator:**
   ```bash
   pnpm run generate:promos
   ```
   This will automatically:
   - Execute the native Flutter test harness (`flutter test test/record_real_app_showcase_test.dart`) to render your actual application UI and capture crisp 1080p frames.
   - Compile `.mp4` (H.264), `.webp`, and 2-pass `.gif` assets via FFmpeg.
   - Generate official Recordly (`.recordly`) project manifests and poster previews.
   - Rebuild the interactive [`docs/design-evidence/promo-gallery.html`](file:///c:/Personale/Repos/pi-crust/pi-crust/docs/design-evidence/promo-gallery.html) showcase gallery.

3. **Preview results:**
   Open `docs/design-evidence/promo-gallery.html` in your browser to inspect all 8 videos side-by-side.

4. **Commit & Release:**
   ```bash
   git add docs/design-evidence/ package.json
   git commit -m "chore(release): update promotional videos and recordly projects"
   ```
