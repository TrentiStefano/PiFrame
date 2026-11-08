"""Post-process Recordly exports into website assets.

For every clip: master.mp4 (edit at full resolution), clip.mp4 (H.264), clip.webm (VP9),
poster.jpg. Edits only cut/speed real footage; clip 01 adds a neutral title card
between the two real recordings.
"""
import json
import shutil
import os
import subprocess
import sys
from pathlib import Path

FF = os.environ.get("FFMPEG") or shutil.which("ffmpeg") or "ffmpeg"
REC = Path(r"C:\demo\rec")
SITE = Path(__file__).resolve().parents[2] / "website" / "assets" / "showcase"
FONT = "C\\:/Windows/Fonts/segoeuib.ttf"
FONT_LIGHT = "C\\:/Windows/Fonts/segoeui.ttf"
W, H = 2384, 1342

# clip -> (source mp4, segments [(start, end, speed)], poster time in edited output)
PLAN = {
    "02-agents-tree": ("02-agents-tree.mp4", [(0, 11.5, 1.6), (11.5, 26, 1), (26, 186, 12), (186, None, 1)], 17.0),
    "07-bento-workspace": ("07-bento-workspace.mp4", None, 1.0),
    "08-review-diff": ("08-review-diff.mp4", None, 6.0),
    "09-git-desk": ("09-git-desk.mp4", None, 4.0),
    "10-repo-add-to-chat": ("10-repo-add-to-chat.mp4", None, 8.2),
    "13-model-context": ("13-model-context.mp4", None, 9.5),
    "15-composer": ("15-composer.mp4", None, 3.0),
    "17-themes": ("17-themes.mp4", None, 8.0),
}


def run(args):
    print(" ".join(str(a) for a in args[:8]), "...")
    subprocess.run([FF, "-v", "error", "-y", *map(str, args)], check=True)


def duration(path: Path) -> float:
    out = subprocess.run([FF.replace("ffmpeg.exe", "ffprobe.exe"), "-v", "error", "-show_entries",
                          "format=duration", "-of", "csv=p=0", str(path)], capture_output=True, text=True)
    return float(out.stdout.strip())


def edit(src: Path, segments, out: Path):
    if not segments:
        shutil.copyfile(src, out)
        return
    total = duration(src)
    parts, labels = [], []
    for i, (a, b, sp) in enumerate(segments):
        b = total if b is None else b
        parts.append(f"[0:v]trim={a}:{b},setpts=(PTS-STARTPTS)/{sp}[v{i}]")
        labels.append(f"[v{i}]")
    fc = ";".join(parts) + f";{''.join(labels)}concat=n={len(labels)}:v=1:a=0,fps=60[out]"
    run(["-i", src, "-filter_complex", fc, "-map", "[out]", "-c:v", "libx264", "-crf", "16",
         "-preset", "slow", "-pix_fmt", "yuv420p", out])


def card(out: Path, line1: str, line2: str, seconds=2.6):
    vf = (f"drawtext=fontfile='{FONT}':text='{line1}':fontcolor=0x141413:fontsize=96:"
          f"x=(w-text_w)/2:y=(h/2)-110,"
          f"drawtext=fontfile='{FONT_LIGHT}':text='{line2}':fontcolor=0x2a688d:fontsize=54:"
          f"x=(w-text_w)/2:y=(h/2)+20,"
          f"fade=t=in:st=0:d=0.35,fade=t=out:st={seconds - 0.35}:d=0.35")
    run(["-f", "lavfi", "-i", f"color=c=0xe9e7e3:s={W}x{H}:r=60:d={seconds}", "-vf", vf,
         "-c:v", "libx264", "-crf", "16", "-pix_fmt", "yuv420p", out])


def concat(inputs, out: Path):
    n = len(inputs)
    args = []
    for p in inputs:
        args += ["-i", p]
    fc = "".join(f"[{i}:v]scale={W}:{H},setsar=1,fps=60[v{i}];" for i in range(n))
    fc += "".join(f"[v{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=0[out]"
    run([*args, "-filter_complex", fc, "-map", "[out]", "-c:v", "libx264", "-crf", "16",
         "-preset", "slow", "-pix_fmt", "yuv420p", out])


def web(master: Path, dest: Path, poster_t: float):
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(master, dest / "master.mp4")
    scale = "scale=1920:-2:flags=lanczos"
    run(["-i", master, "-vf", scale, "-c:v", "libx264", "-crf", "24", "-preset", "slow",
         "-profile:v", "high", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", dest / "clip.mp4"])
    run(["-i", master, "-vf", scale, "-c:v", "libvpx-vp9", "-crf", "34", "-b:v", "0", "-row-mt", "1",
         "-deadline", "good", "-cpu-used", "2", "-an", dest / "clip.webm"])
    run(["-ss", poster_t, "-i", master, "-frames:v", "1", "-vf", scale, "-q:v", "3", dest / "poster.jpg"])


def main(only=None):
    tmp = REC / "edit"
    tmp.mkdir(exist_ok=True)
    for name, (src, segs, poster_t) in PLAN.items():
        if only and name not in only:
            continue
        master = tmp / f"{name}.mp4"
        edit(REC / src, segs, master)
        web(master, SITE / name, poster_t)
    if not only or "01-disconnect-safe" in only:
        c = tmp / "01-card.mp4"
        card(c, "Window closed.", "pi-agentd kept the agent working in the background")
        master = tmp / "01-disconnect-safe.mp4"
        concat([REC / "01a-disconnect.mp4", c, REC / "01b-reopen.mp4"], master)
        web(master, SITE / "01-disconnect-safe", duration(master) - 3)


if __name__ == "__main__":
    main(sys.argv[1:] or None)
