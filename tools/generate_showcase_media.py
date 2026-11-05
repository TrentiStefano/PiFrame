import os
import subprocess
import sys

def run_cmd(cmd):
    print("Running:", " ".join(cmd))
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print("ERROR:", res.stderr)
        sys.exit(1)

os.makedirs("website/assets/img/ui", exist_ok=True)
os.makedirs("website/assets/video", exist_ok=True)

# 1. GENERATE THE 11 RECORDLY-STYLE ANIMATED GIFS
gif_tasks = [
    {
        "src": "docs/design-evidence/recordly-projects/clip-04-steer-queue.preview.png",
        "dst": "website/assets/img/ui/feature-01-agent-questions.gif",
        "vf": "zoompan=z='min(zoom+0.002,1.10)':d=45:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=800x500:fps=15,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=bayer"
    },
    {
        "src": "docs/design-evidence/recordly-projects/clip-01-bento-workspace.preview.png",
        "dst": "website/assets/img/ui/feature-04-file-drag-drop-attach.gif",
        "vf": "zoompan=z='min(zoom+0.0025,1.12)':d=45:x='iw*0.5-(iw/zoom/2)':y='ih*0.75-(ih/zoom/2)':s=800x500:fps=15,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=bayer"
    },
    {
        "src": "docs/design-evidence/recordly-projects/clip-08-git-staging.preview.png",
        "dst": "website/assets/img/ui/feature-05-review-changes-50-50-diff.gif",
        "vf": "zoompan=z=1.05:d=45:x='iw/2-(iw/zoom/2)':y='(on/45)*(ih-ih/zoom)':s=800x500:fps=15,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=bayer"
    },
    {
        "src": "docs/design-evidence/recordly-projects/clip-08-git-staging.preview.png",
        "dst": "website/assets/img/ui/feature-06-git-changes-staging.gif",
        "vf": "zoompan=z='min(zoom+0.002,1.12)':d=45:x='iw*0.7-(iw/zoom/2)':y='ih*0.4-(ih/zoom/2)':s=800x500:fps=15,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=bayer"
    },
    {
        "src": "docs/design-evidence/recordly-projects/clip-01-bento-workspace.preview.png",
        "dst": "website/assets/img/ui/feature-07-web-browser-pane.gif",
        "vf": "zoompan=z='min(zoom+0.0018,1.08)':d=45:x='iw*0.7-(iw/zoom/2)':y='ih*0.3-(ih/zoom/2)':s=800x500:fps=15,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=bayer"
    },
    {
        "src": "docs/design-evidence/recordly-projects/clip-03-code-search.preview.png",
        "dst": "website/assets/img/ui/feature-08-repo-search-add-to-chat.gif",
        "vf": "zoompan=z='min(zoom+0.002,1.10)':d=45:x='iw*0.35-(iw/zoom/2)':y='ih*0.35-(ih/zoom/2)':s=800x500:fps=15,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=bayer"
    },
    {
        "src": "docs/design-evidence/bento-triptych-fixture-dark-compact-files.png",
        "dst": "website/assets/img/ui/feature-09-pane-resize-and-terminal.gif",
        "vf": "zoompan=z='min(zoom+0.002,1.12)':d=45:x='iw*0.5-(iw/zoom/2)':y='ih*0.6-(ih/zoom/2)':s=800x500:fps=15,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=bayer"
    },
    {
        "src": "docs/design-evidence/recordly-projects/clip-09-session-tree.preview.png",
        "dst": "website/assets/img/ui/feature-10-rename-and-pin-session.gif",
        "vf": "zoompan=z='min(zoom+0.002,1.12)':d=45:x='iw*0.2-(iw/zoom/2)':y='ih*0.3-(ih/zoom/2)':s=800x500:fps=15,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=bayer"
    },
    {
        "src": "docs/design-evidence/bento-triptych-fixture-wide.png",
        "dst": "website/assets/img/ui/feature-11-light-mode-pane-checklist.gif",
        "vf": "zoompan=z='min(zoom+0.002,1.10)':d=45:x='iw*0.5-(iw/zoom/2)':y='ih*0.2-(ih/zoom/2)':s=800x500:fps=15,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=bayer"
    },
    {
        "src": "docs/design-evidence/recordly-projects/clip-06-reasoning-stream.preview.png",
        "dst": "website/assets/img/ui/feature-18-click-file-open-explorer.gif",
        "vf": "zoompan=z='min(zoom+0.0022,1.12)':d=45:x='iw*0.5-(iw/zoom/2)':y='ih*0.5-(ih/zoom/2)':s=800x500:fps=15,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=bayer"
    },
    {
        "src": "docs/design-evidence/recordly-projects/02_instruction_dialog.png",
        "dst": "website/assets/img/ui/feature-20-generate-repo-instructions.gif",
        "vf": "zoompan=z='min(zoom+0.0018,1.08)':d=45:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=800x500:fps=15,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse=dither=bayer"
    }
]

print(f"Generating {len(gif_tasks)} Recordly-style animated feature clips...")
for t in gif_tasks:
    cmd = [
        "ffmpeg", "-y",
        "-i", t["src"],
        "-vf", t["vf"],
        t["dst"]
    ]
    run_cmd(cmd)
    print("Generated:", t["dst"])

# 2. GENERATE THE 10-SECOND HERO SHOWCASE VIDEO (MP4 & WEBM)
# Scene 1: 0.0 - 2.0s (Impeller 120fps Hook)
# Scene 2: 2.0 - 5.0s (50/50 Split Diff & Staging)
# Scene 3: 5.0 - 7.5s (Light Mode & Bento Workspace)
# Scene 4: 7.5 - 10.0s (Outro & Daemon Resilience)

print("Composing 10-second Hero Showcase Video...")

filter_complex = (
    # Scene 1: 2.0s
    "[0:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,zoompan=z='min(zoom+0.001,1.06)':d=60:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1280x720:fps=30,trim=duration=2.0,setpts=PTS-STARTPTS[v0];"
    # Scene 2: 3.0s
    "[1:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,zoompan=z='min(zoom+0.001,1.06)':d=90:x='iw*0.6-(iw/zoom/2)':y='ih*0.4-(ih/zoom/2)':s=1280x720:fps=30,trim=duration=3.0,setpts=PTS-STARTPTS[v1];"
    # Scene 3: 2.5s
    "[2:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,zoompan=z='min(zoom+0.001,1.06)':d=75:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1280x720:fps=30,trim=duration=2.5,setpts=PTS-STARTPTS[v2];"
    # Scene 4: 2.5s
    "[3:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,zoompan=z='min(zoom+0.001,1.06)':d=75:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1280x720:fps=30,trim=duration=2.5,setpts=PTS-STARTPTS[v3];"
    # Concat all 4 scenes -> 10.0s total
    "[v0][v1][v2][v3]concat=n=4:v=1:a=0[v]"
)

# Render MP4 (H.264)
mp4_cmd = [
    "ffmpeg", "-y",
    "-i", "docs/design-evidence/bento-triptych-fixture-dark-wide.png",
    "-i", "docs/design-evidence/recordly-projects/clip-08-git-staging.preview.png",
    "-i", "docs/design-evidence/bento-triptych-fixture-wide.png",
    "-i", "docs/design-evidence/recordly-projects/clip-11-disconnect-safe.preview.png",
    "-filter_complex", filter_complex,
    "-map", "[v]",
    "-c:v", "libx264",
    "-pix_fmt", "yuv420p",
    "-profile:v", "high",
    "-level", "4.0",
    "-movflags", "+faststart",
    "-r", "30",
    "website/assets/video/hero-10s-piframe-showcase.mp4"
]
run_cmd(mp4_cmd)
print("Rendered: website/assets/video/hero-10s-piframe-showcase.mp4")

# Render WebM (VP9)
webm_cmd = [
    "ffmpeg", "-y",
    "-i", "docs/design-evidence/bento-triptych-fixture-dark-wide.png",
    "-i", "docs/design-evidence/recordly-projects/clip-08-git-staging.preview.png",
    "-i", "docs/design-evidence/bento-triptych-fixture-wide.png",
    "-i", "docs/design-evidence/recordly-projects/clip-11-disconnect-safe.preview.png",
    "-filter_complex", filter_complex,
    "-map", "[v]",
    "-c:v", "libvpx-vp9",
    "-b:v", "1500k",
    "-crf", "30",
    "-r", "30",
    "website/assets/video/hero-10s-piframe-showcase.webm"
]
run_cmd(webm_cmd)
print("Rendered: website/assets/video/hero-10s-piframe-showcase.webm")

print("All Step 4 assets generated successfully!")
