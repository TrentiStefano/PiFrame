# Hyperframes Composition Brief: PiFrame Desktop Promo

## Objective
Create a high-energy launch video for PiFrame Desktop highlighting its native Flutter desktop architecture, disconnect-safe daemon, live subagent hierarchy, Bento ergonomics, split-diff code review, and 100% local privacy.

## Deliverables
- **1080p Master Video**: `brag-output/piframe-promo-1080p.mp4` (1920×1080, 16:9 widescreen)
- **Social Cut Video**: `brag-output/piframe-promo-social.mp4` (1080×1350, 4:5 portrait)
- **Web Optimized MP4**: `website/assets/video/piframe-promo.mp4` (H.264 High profile, faststart, <= 8MB)
- **Web Optimized WebM**: `website/assets/video/piframe-promo.webm` (VP9, <= 8MB)
- **High-Res Poster Frame**: `website/assets/video/piframe-promo-poster.jpg` (settled frame extracted from 1080p master)

## Duration
- Total Duration: **26.5 seconds** (meets 24–30s requirement)
- 6 sequential beats (each 4.0s–5.0s, using 3.5s–4.5s clip trims)

## Visual Identity & Palette
- **Canvas Backdrop**: `#eeede9` (Neutral Light Gray/Beige matching showcase masters `#eeede9`..`#e2e0da`)
- **Primary Ink / Dark Elements**: `#161c27` (PiFrame Dark theme base)
- **Accent Blue**: `#5f9fc5` (PiFrame Brand Blue)
- **Thinking Accent**: `#81b2cf`
- **Secondary Ink**: `#475569`
- **Borders**: `rgba(0, 0, 0, 0.08)` on light / `#2e3c53` on dark
- **Fonts**: `Inter`, `Outfit`, `Plus Jakarta Sans`, `sans-serif`
- **Icon**: `docs/design-evidence/icons/piframe-dark-1024.png`

## Audio Contract
- **Music Track**: `happy-beats-business-moves-vol-12-by-ende-dot-app.mp3` (from `.agents/skills/brag/assets/music/`)
- **Tempo**: 109.96 BPM
- **License**: CC BY 4.0 by Sascha Ende, ende.app ("Music: Sascha Ende, ende.app (CC BY 4.0)")
- **Treatment**: Starts at 0.0s at volume 0.35 with 0.5s fade-in; hits rhythmic beat locks at scene cuts; fades to silence over 1.5s at 25.0s–26.5s.
- **SFX**: Tasteful interface clicks and impact cues from Kenney.nl (CC0):
  - Beat 1 (0.1s): `impactSoft_medium_001.ogg`
  - Beat 2 (4.5s): `drop_001.ogg`
  - Beat 3 (8.5s): `click_001.ogg`
  - Beat 4 (13.0s): `drop_002.ogg`
  - Beat 5 (17.5s): `switch_001.ogg`
  - Beat 6 (21.84s): `impactBell_heavy_000.ogg` (outro payoff lock)

## Per-Beat Specifications & Clip In/Out Parameters
```json
{
  "beat1": {
    "slug": "01-disconnect-safe",
    "clipStart": 1.0,
    "clipEnd": 5.5,
    "duration": 4.5,
    "badge": "DECOUPLED DAEMON",
    "headline": "Window Closed. Agent Never Stops.",
    "subhead": "pi-agentd background daemon preserves in-flight work when UI exits."
  },
  "beat2": {
    "slug": "02-agents-tree",
    "clipStart": 0.5,
    "clipEnd": 4.5,
    "duration": 4.0,
    "badge": "MULTI-AGENT ENGINE",
    "headline": "Live Agent Tree & Cost Tracking",
    "subhead": "Real-time subagent inspection, token metrics, and parallel execution."
  },
  "beat3": {
    "slug": "07-bento-workspace",
    "clipStart": 1.0,
    "clipEnd": 5.5,
    "duration": 4.5,
    "badge": "NATIVE FLUTTER DESKTOP",
    "headline": "Adaptive Bento Workspace",
    "subhead": "Three co-visible panes with fluid resizing and zero webview bloat."
  },
  "beat4": {
    "slug": "08-review-diff",
    "clipStart": 0.5,
    "clipEnd": 5.0,
    "duration": 4.5,
    "badge": "CODE REVIEW & GIT",
    "headline": "50/50 Synchronized Split Diff",
    "subhead": "Review changes inline with one-click atomic file staging."
  },
  "beat5": {
    "slug": "17-themes",
    "clipStart": 0.5,
    "clipEnd": 4.5,
    "duration": 4.0,
    "badge": "LOCAL-FIRST PRIVACY",
    "headline": "Zero Telemetry. 100% Local.",
    "subhead": "Your tokens and code stay local. Instant PiFrame Dark / Light palette toggle."
  },
  "beat6": {
    "slug": "outro",
    "duration": 5.0,
    "title": "PiFrame",
    "tagline": "The Native Desktop GUI for pi-coding-agent",
    "platforms": "Windows · macOS · Linux",
    "repo": "github.com/TrentiStefano/piframe"
  }
}
```

## Grounding & Strict Integrity Rules
- The application UI must strictly originate from real screen recordings. Never simulate, draw, or mock Flutter UI components in HTML/CSS/canvas.
- In pipeline testing, neutral test clips with solid `#e9e7e3` and text 'TEST CLIP' are used until real master clips are recorded.
- Only verifiable claims: Native Flutter, Decoupled Daemon, Zero Telemetry, Windows/macOS/Linux.
