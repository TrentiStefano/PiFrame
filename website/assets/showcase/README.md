# PiFrame Showcase Assets Specification

This directory holds the official media assets for the 10 featured product chapters of the PiFrame showcase website.

All UI media must adhere to the **Strict Repository Rules** defined in `AGENTS.md`:
- **Real UI captures only**: Never invent, sketch, or code simulated UI mockups in HTML/CSS/canvas to represent the PiFrame application interface.
- **Authentic data only**: No personal data (no private paths, usernames, or real auth tokens), and no fabricated metrics.

---

## 1. Directory Structure & Required Filenames

```
website/assets/
├── video/
│   ├── piframe-promo.mp4           # Hero 20-30s promo video (H.264, 1080p60)
│   ├── piframe-promo.webm          # Hero promo video (AV1 or VP9)
│   └── piframe-promo-poster.jpg    # Hero promo high-res poster fallback (<= 200 KB)
└── showcase/
    ├── 01-disconnect-safe/
    │   ├── clip.mp4                # H.264 video (1920x1080 or 1600x1000, 30-60 fps, <= 2.5 MB)
    │   ├── clip.webm               # VP9/AV1 video (<= 1.5 MB)
    │   └── poster.jpg              # First frame / high-res poster (<= 150 KB)
    ├── 02-agents-tree/
    │   ├── clip.mp4
    │   ├── clip.webm
    │   └── poster.jpg
    ├── 07-bento-workspace/
    │   ├── clip.mp4
    │   ├── clip.webm
    │   └── poster.jpg
    ├── 08-review-diff/
    │   ├── clip.mp4
    │   ├── clip.webm
    │   └── poster.jpg
    ├── 09-git-desk/
    │   ├── clip.mp4
    │   ├── clip.webm
    │   └── poster.jpg
    ├── 10-repo-add-to-chat/
    │   ├── clip.mp4
    │   ├── clip.webm
    │   └── poster.jpg
    ├── 13-model-context/
    │   ├── clip.mp4
    │   ├── clip.webm
    │   └── poster.jpg
    ├── 15-composer/
    │   ├── clip.mp4
    │   ├── clip.webm
    │   └── poster.jpg
    ├── 17-themes/
    │   ├── clip.mp4
    │   ├── clip.webm
    │   └── poster.jpg
    └── 18-remote/
        ├── settings.png            # Desktop Remote settings page capture (PiFrame UI)
        ├── iphone.png              # Mobile browser client capture for iPhone device frame
        ├── clip.mp4                # (Optional) Side-by-side walkthrough clip
        ├── clip.webm               # (Optional) WebM format
        └── poster.jpg              # (Optional) Poster frame
```

---

## 2. Chapter Specifications

| Slug | Feature Name | Core Story to Illustrate | Video Format / Specs |
|---|---|---|---|
| `01-disconnect-safe` | Disconnect-Safe Daemon | Window closes mid-stream; on reopen `pi-agentd` seamlessly catches up all tokens without loss. | `clip.mp4`, `clip.webm`, `poster.jpg` (5–8s loop) |
| `02-agents-tree` | Live Subagents Tree | Live background agent hierarchy displaying subagent model, cost tracking, status, and activity pulses. | `clip.mp4`, `clip.webm`, `poster.jpg` (5–8s loop) |
| `07-bento-workspace` | Bento Triptych Workspace | Three co-visible panes (Repo Explorer/Code, Chat Session, Git/Browser) with resizable splitters and collapsible panes. | `clip.mp4`, `clip.webm`, `poster.jpg` (5–8s loop) |
| `08-review-diff` | Review Changes 50/50 Split Diff | Side-by-side synchronized diff inspector inside the chat turn, staging toggle, and clean diff views. | `clip.mp4`, `clip.webm`, `poster.jpg` (5–8s loop) |
| `09-git-desk` | Git Changes Desk & Stash | Stage files, write commit message, branch picker with search, and safe auto-stash dialog on dirty switch. | `clip.mp4`, `clip.webm`, `poster.jpg` (5–8s loop) |
| `10-repo-add-to-chat` | Repo Explorer → Add to Chat | Browse repository files, select line ranges, click "Add to Chat" to insert context chips, live Markdown rendering. | `clip.mp4`, `clip.webm`, `poster.jpg` (5–8s loop) |
| `13-model-context` | Model, Thinking & Context Analytics | Model picker, thinking depth chips, context tier switcher (272k / 1M), and custom compaction margin settings. | `clip.mp4`, `clip.webm`, `poster.jpg` (5–8s loop) |
| `15-composer` | Expanded Composer & File Mentions | `@` file mentions, `/` slash commands (Pi built-ins), drag-and-drop file attachments, and expandable composer overlay. | `clip.mp4`, `clip.webm`, `poster.jpg` (5–8s loop) |
| `17-themes` | Real-Time Theme Editor & Switch | Instant PiFrame Dark / PiFrame Light toggling, token color picker, and live UI preview with VSCode import. | `clip.mp4`, `clip.webm`, `poster.jpg` (5–8s loop) |
| `18-remote` | Remote Control via Tailscale | Secure remote control on mobile over Tailscale: desktop Remote settings page paired with real mobile web interface. | `settings.png` + `iphone.png` (or video loop) |

---

## 3. Video Encoding Guidelines

1. **Resolution & Aspect Ratio**: 16:9 widescreen (1920×1080) or native window capture (1600×1000) framed on neutral `#eeede9` / dark `#161c27` canvas.
2. **WebM Encoding (AV1 or VP9)**:
   ```bash
   ffmpeg -i master.mp4 -c:v libvpx-vp9 -b:v 1200k -crf 30 -an clip.webm
   ```
3. **MP4 Encoding (H.264 High Profile)**:
   ```bash
   ffmpeg -i master.mp4 -c:v libx264 -pix_fmt yuv420p -profile:v high -crf 22 -preset slow -movflags +faststart -an clip.mp4
   ```
4. **Poster Extraction (JPEG)**:
   ```bash
   ffmpeg -ss 00:00:01.000 -i clip.mp4 -frames:v 1 -q:v 2 poster.jpg
   ```
5. **Autoplay Requirements**:
   - Audio tracks must be stripped (`-an`) for reliable browser autoplay.
   - Target payload: `< 1.8 MB` per clip to ensure fast mobile page loads and LCP < 2.5s.

---

## 4. Fallback Handling on the Showcase Website

The website dynamically tests asset presence using asynchronous `HEAD` requests. Until a chapter's video files exist on disk:
- The website renders a high-craft CSS-only neutral placeholder (16:9 aspect ratio, dark `#161c27` chassis framing, recording status indicator, and chapter metadata).
- As soon as clips and posters are exported into the directory, the JavaScript engine swaps to the active video player seamlessly on next page load without code modification.
