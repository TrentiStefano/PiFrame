"""Re-encode showcase clips for the website: 1280 px wide, 30 fps, two-pass to a
size budget (default 1.4 MB). Reads website/assets/showcase/<slug>/master.mp4
(never modified) and writes clip.webm (VP9), clip.mp4 (H.264), poster.webp,
poster.jpg (1280 px).

usage: python web_encode.py [slug ...]
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

FF = os.environ.get("FFMPEG") or shutil.which("ffmpeg") or "ffmpeg"
FP = FF.replace("ffmpeg.exe", "ffprobe.exe")
SITE = Path(__file__).resolve().parents[2] / "website" / "assets" / "showcase"
BUDGET = 1.40 * 1024 * 1024  # bytes per file
POSTER_T = {"01-disconnect-safe": 29.0, "02-agents-tree": 17.0, "07-bento-workspace": 1.0,
            "08-review-diff": 6.0, "09-git-desk": 4.0, "10-repo-add-to-chat": 8.2,
            "13-model-context": 9.5, "15-composer": 3.0, "17-themes": 8.0}
VF = "scale=1280:-2:flags=lanczos,fps=30"


def run(args):
    subprocess.run([FF, "-v", "error", "-y", *map(str, args)], check=True)


def duration(p):
    r = subprocess.run([FP, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(p)],
                       capture_output=True, text=True)
    return float(r.stdout.strip())


def encode(slug):
    d = SITE / slug
    src = d / "master.mp4"
    dur = duration(src)
    kbps = int(BUDGET * 8 / dur / 1000 * 0.94)
    tmp = Path(tempfile.gettempdir()) / f"pf2pass-{slug}"
    # VP9 two-pass
    run(["-i", src, "-vf", VF, "-c:v", "libvpx-vp9", "-b:v", f"{kbps}k", "-pass", "1", "-passlogfile", tmp,
         "-row-mt", "1", "-deadline", "good", "-cpu-used", "4", "-an", "-f", "webm", "NUL"])
    run(["-i", src, "-vf", VF, "-c:v", "libvpx-vp9", "-b:v", f"{kbps}k", "-pass", "2", "-passlogfile", tmp,
         "-row-mt", "1", "-deadline", "good", "-cpu-used", "1", "-an", d / "clip.webm"])
    # H.264 two-pass
    run(["-i", src, "-vf", VF, "-c:v", "libx264", "-preset", "slow", "-b:v", f"{kbps}k", "-pass", "1",
         "-passlogfile", tmp, "-an", "-f", "mp4", "NUL"])
    run(["-i", src, "-vf", VF, "-c:v", "libx264", "-preset", "slow", "-b:v", f"{kbps}k", "-pass", "2",
         "-passlogfile", tmp, "-profile:v", "high", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an",
         d / "clip.mp4"])
    t = POSTER_T.get(slug, 2.0)
    run(["-ss", t, "-i", src, "-frames:v", "1", "-vf", "scale=1280:-2:flags=lanczos", "-q:v", "4", d / "poster.jpg"])
    run(["-ss", t, "-i", src, "-frames:v", "1", "-vf", "scale=1280:-2:flags=lanczos", "-c:v", "libwebp",
         "-quality", "78", d / "poster.webp"])
    sizes = {f.name: round(f.stat().st_size / 1048576, 2) for f in d.iterdir() if f.name != "master.mp4"}
    print(slug, f"{dur:.1f}s", f"{kbps}kbps", sizes)


if __name__ == "__main__":
    for slug in (sys.argv[1:] or sorted(POSTER_T)):
        encode(slug)
