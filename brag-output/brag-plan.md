# Brag Plan: PiFrame Desktop

## What is this app?
PiFrame is a native Flutter desktop GUI for `pi-coding-agent` featuring a decoupled disconnect-safe daemon, adaptive Bento ergonomics, synchronized split-diff reviews, and zero telemetry.

## The angle
Most AI coding agent GUIs are sluggish Electron webview wrappers that freeze during large token streams, leak usage telemetry, and kill in-flight agent tasks if the window closes. PiFrame proves developer tools should be native, instant, and disconnect-safe: when the window closes, the background daemon keeps the agent running uninterrupted.

## Hook (first 2-3 seconds)
An immediate, assertive hook pairing the disconnect-safe daemon with the multi-agent hierarchy:
Visual: A terminal/window closes mid-stream; the daemon continues execution seamlessly and catches up the entire transcript upon reconnect.
Tagline: **"Window Closed. Agent Never Stops."**
Accent badge: `#5f9fc5` on `#161c27` dark pill.

## Key moments (the middle)
- **Disconnect-Safe Daemon (`01-disconnect-safe`)**: Decoupled `pi-agentd` background process keeps agent reasoning and tool executions running even when the UI window closes.
- **Live Subagent Tree (`02-agents-tree`)**: Interactive background agent hierarchy showing subagent models, real-time cost tracking, status badges, and activity pulses.
- **Adaptive Bento Workspace (`07-bento-workspace`)**: Three co-visible resizable panes (Repo Explorer/Code, Chat Session, Git Desk/Browser) rendered natively by Flutter.
- **50/50 Split Diff Review (`08-review-diff`)**: Synchronized side-by-side code review inside chat turns with one-click atomic file staging.
- **Local Privacy & Adaptive Themes (`17-themes`)**: Zero telemetry, 100% local-only operation, with instant palette switching between PiFrame Dark and PiFrame Light.

## Outro / punchline
A sharp landing on the glowing PiFrame icon with verifiable facts:
- **"PiFrame: The Native Desktop GUI for pi-coding-agent"**
- **"Disconnect-Safe Daemon · Zero Telemetry · Native Flutter"**
- Badges: **"Windows · macOS · Linux"**
- URL: **"github.com/TrentiStefano/piframe"**

## User flow worth showing
1. **In-Flight Autonomous Execution**: An agent session runs complex multi-file edits; user closes the GUI window to attend to other work.
2. **Seamless Catch-up**: User relaunches PiFrame; the daemon instantly catches up the transcript, showing completed diffs and subagent execution logs with zero lost state.
3. **50/50 Code Review & Staging**: User inspects the changes side-by-side and commits directly from the integrated Git Desk.

## Tone
- Preset: `polished`
- Creative direction: "Tactile, high-velocity native developer tool with clean typography, rhythmic musical pacing, and unapologetic desktop performance"
- Interpretation: Restrained transitions, strict adherence to real recorded footage, strong typographic contrast, and verifiable claims only.

## Formats & Resolution
- **Hero Landscape**: 1920×1080 (16:9 widescreen) — `piframe-promo-1080p.mp4`
- **Social Cut**: 1080×1350 (4:5 portrait) — `piframe-promo-social.mp4`
- **Target Web Master**: 1920×1080 (16:9 H.264 High profile, <= 8MB) — `website/assets/video/piframe-promo.mp4`
- **Web VP9 Master**: 1920×1080 (WebM) — `website/assets/video/piframe-promo.webm`
- **Poster Still**: Settled 1080p frame — `website/assets/video/piframe-promo-poster.jpg`

## Total Duration: 26.5 seconds (Within 24–30s window)

## Visual identity (from the project)
- Neutral Canvas Backdrop: `#eeede9` (matching real showcase captures `#eeede9`..`#e2e0da`)
- Ink / Dark Container: `#161c27` (PiFrame Dark theme)
- Accent Blue: `#5f9fc5` (PiFrame Brand Blue)
- Thinking Accent: `#81b2cf`
- Secondary / Subhead Ink: `#475569`
- Subtle Borders: `rgba(0, 0, 0, 0.08)` on light / `#2e3c53` on dark
- Display font: `Outfit`, `Inter`, `sans-serif`
- Code font: `JetBrains Mono`, `monospace`
- Real Outro Icon: `docs/design-evidence/icons/piframe-dark-1024.png`

## Audio direction & Licensing
- **Music Track**: `happy-beats-business-moves-vol-12-by-ende-dot-app.mp3`
- **Composer / Source**: Sascha Ende ([ende.app](https://ende.app/en)), "Happy Beats / Business Moves Vol. 12"
- **License**: Creative Commons Attribution 4.0 International ([CC BY 4.0](https://ende.app/en/standard-license)). Attribution credit: "Music: Sascha Ende, ende.app (CC BY 4.0)".
- **Tempo**: 109.96 BPM (steady, polished, confident groove)
- **SFX**: Kenney.nl interface and impact soundpack (CC0 / Public Domain)
- **Audio Arc**: Starts with clean punch at 0.0s (0.5s fade-in), hits rhythmic beat locks at scene boundaries, swells gently at the outro logo reveal (21.8s), and fades out over 1.5s at 25.0s–26.5s.

## Music Cue Guidance & Beat-Lock Alignment
- Track duration: 117.36s (we use the first 26.5s)
- Strong cues:
  - `4.39s` (Beat 1 → Beat 2 transition at `4.5s`, lock within 0.11s)
  - `8.74s` (Beat 2 → Beat 3 transition at `8.5s`, lock within 0.24s)
  - `13.11s` (Beat 3 → Beat 4 transition at `13.0s`, lock within 0.11s)
  - `17.47s` (Beat 4 → Beat 5 transition at `17.5s`, lock within 0.03s)
  - `21.84s` (Beat 5 → Beat 6 Outro transition at `21.5s`, lock within 0.34s)
  - `22.93s` / `24.56s` (Strong cues for platform badges and URL reveal)

---

## Beat-by-Beat Storyboard (Total: 26.5s)

### Beat 1 — The Disconnect-Safe Hook (0.0s – 4.5s, 4.5s)
- **Clip Slug**: `01-disconnect-safe` (source: `website/assets/showcase/01-disconnect-safe/master.mp4`)
- **Tuning Parameters**:
  - `clipStart`: 1.0s
  - `clipEnd`: 5.5s
  - `duration`: 4.5s
- **Typographic Overlay**:
  - Badge: `DECOUPLED DAEMON` (Accent `#5f9fc5` on `#161c27` pill)
  - Headline: `Window Closed. Agent Never Stops.`
  - Subhead: `pi-agentd background daemon preserves in-flight work when UI exits.`
- **Audio Intent**: High-confidence intro, volume 0.35; soft impact at 0.1s.
- **Transition**: Clean fade cut → Beat 2.

### Beat 2 — Live Subagent Hierarchy (4.5s – 8.5s, 4.0s)
- **Clip Slug**: `02-agents-tree` (source: `website/assets/showcase/02-agents-tree/master.mp4`)
- **Tuning Parameters**:
  - `clipStart`: 0.5s
  - `clipEnd`: 4.5s
  - `duration`: 4.0s
- **Typographic Overlay**:
  - Badge: `MULTI-AGENT ENGINE`
  - Headline: `Live Agent Tree & Cost Tracking`
  - Subhead: `Real-time subagent inspection, token metrics, and parallel execution.`
- **Audio Intent**: Drum groove continues; subtle drop SFX (`drop_001.ogg`) at 4.5s.
- **Transition**: Clean slide → Beat 3.

### Beat 3 — Adaptive Bento Ergonomics (8.5s – 13.0s, 4.5s)
- **Clip Slug**: `07-bento-workspace` (source: `website/assets/showcase/07-bento-workspace/master.mp4`)
- **Tuning Parameters**:
  - `clipStart`: 1.0s
  - `clipEnd`: 5.5s
  - `duration`: 4.5s
- **Typographic Overlay**:
  - Badge: `NATIVE FLUTTER DESKTOP`
  - Headline: `Adaptive Bento Workspace`
  - Subhead: `Three co-visible panes with fluid resizing and zero webview bloat.`
- **Audio Intent**: Subtle click SFX (`click_001.ogg`) at 8.5s.
- **Transition**: Clean cut → Beat 4.

### Beat 4 — 50/50 Split Diff Code Review (13.0s – 17.5s, 4.5s)
- **Clip Slug**: `08-review-diff` (source: `website/assets/showcase/08-review-diff/master.mp4`)
- **Tuning Parameters**:
  - `clipStart`: 0.5s
  - `clipEnd`: 5.0s
  - `duration`: 4.5s
- **Typographic Overlay**:
  - Badge: `CODE REVIEW & GIT`
  - Headline: `50/50 Synchronized Split Diff`
  - Subhead: `Review changes inline with one-click atomic file staging.`
- **Audio Intent**: Soft UI sound (`drop_002.ogg`) at 13.0s.
- **Transition**: Clean slide → Beat 5.

### Beat 5 — Zero Telemetry & Themes (17.5s – 21.5s, 4.0s)
- **Clip Slug**: `17-themes` (source: `website/assets/showcase/17-themes/master.mp4`)
- **Tuning Parameters**:
  - `clipStart`: 0.5s
  - `clipEnd`: 4.5s
  - `duration`: 4.0s
- **Typographic Overlay**:
  - Badge: `LOCAL-FIRST PRIVACY`
  - Headline: `Zero Telemetry. 100% Local.`
  - Subhead: `Your tokens and code stay local. Instant PiFrame Dark / Light palette toggle.`
- **Audio Intent**: Toggle SFX (`switch_001.ogg`) at 17.5s, aligning with beat `17.47s`.
- **Transition**: Soft zoom / crossfade → Beat 6.

### Beat 6 — The Outro Punchline (21.5s – 26.5s, 5.0s)
- **Visual**:
  - Real PiFrame dark icon (`docs/design-evidence/icons/piframe-dark-1024.png`)
  - Title: `PiFrame`
  - Tagline: `The Native Desktop GUI for pi-coding-agent`
  - Platform Pills: `Windows · macOS · Linux`
  - Repository Link: `github.com/TrentiStefano/piframe`
- **Tuning Parameters**:
  - `duration`: 5.0s
- **Audio Intent**: Heavy impact bell (`impactBell_heavy_000.ogg`) at `21.84s` strong cue; music volume fades down to silence at `26.5s`.

---

## Verifiable Claims Registry
All claims asserted in this video are grounded in repository source code and documentation:
1. **"Native Flutter Desktop GUI"**: Built with Flutter 3.x / Dart for desktop (`windows/`, `macos/`, `linux/`), compiled natively to machine code without Chromium or Electron wrappers.
2. **"Decoupled Disconnect-Safe Daemon"**: Background service (`pi-agentd`) runs as an independent daemon. Closing the GUI window does not terminate agent processes; reopening the window reconnects to the live session.
3. **"Zero Telemetry / 100% Local"**: No analytical tracking, third-party beacons, or telemetry backends.
4. **"Windows · macOS · Linux"**: Native desktop release targets defined in `pubspec.yaml` and CI workflows.
5. **"Bento Workspace & 50/50 Split Diff"**: Tri-pane bento architecture and side-by-side diff inspector implemented in `lib/widgets/bento/` and `lib/widgets/diff/`.

## Share Copy (Canonical)
Built PiFrame: A native Flutter desktop GUI for pi-coding-agent with a disconnect-safe background daemon, Bento ergonomics, split diffs, and zero telemetry. Free and open source on Windows, macOS, and Linux: github.com/TrentiStefano/piframe
