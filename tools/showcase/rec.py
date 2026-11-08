"""Record a PiFrame clip with Recordly and export it through Recordly's renderer.

Flow per clip:
  1. start Recordly (CDP port 9333), select the PiFrame window, start recording
  2. run the clip driver (marks timestamps + positions of key actions)
  3. stop, wait for the raw recording, close Recordly
  4. write a .recordly project (neutral background, frame, zooms, trims, speed)
  5. export with Recordly's smoke-export mode at source resolution, 60 fps
"""
from __future__ import annotations

import glob
import json
import os
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

import pf

HERE = Path(__file__).parent
RECORDLY = r"C:\Program Files\Recordly\Recordly.exe"
REC_DIR = Path(os.environ["APPDATA"]) / "Recordly" / "recordings"
OUT = Path(r"C:\demo\rec")
OUT.mkdir(parents=True, exist_ok=True)

STYLE = {
    "wallpaper": "linear-gradient(180deg, #eeede9 0%, #e2e0da 100%)",
    "shadowIntensity": 0.42,
    "backgroundBlur": 0,
    "borderRadius": 1.4,
    "padding": {"top": 9, "bottom": 9, "left": 9, "right": 9, "linked": True},
    "aspectRatio": "16:9",
    "showCursor": True,
    "cursorSize": 1.5,
    "cursorClickEffect": "ring",
    "cursorClickEffectColor": "#5f9fc5",
    "connectZooms": True,
    "zoomInDurationMs": 700,
    "zoomOutDurationMs": 700,
}


def node(*args: str, timeout: float = 30) -> str:
    r = subprocess.run(["node", str(HERE / "recordly.mjs"), *args], capture_output=True, text=True, timeout=timeout)
    return (r.stdout + r.stderr).strip()


def kill_recordly() -> None:
    subprocess.run(["taskkill", "/IM", "Recordly.exe", "/F"], capture_output=True)
    time.sleep(1.5)


def start_recordly() -> None:
    kill_recordly()
    subprocess.Popen([RECORDLY, "--remote-debugging-port=9333"], cwd=str(Path(RECORDLY).parent),
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(60):
        try:
            if "hud-overlay" in node("targets", timeout=5):
                break
        except Exception:
            pass
        time.sleep(0.5)
    time.sleep(1.5)
    node("eval", "hud", "window.electronAPI.setCountdownDelay(0)")
    node("eval", "hud", "window.electronAPI.setHudOverlayCaptureProtection(true)")


@dataclass
class Clip:
    name: str
    marks: list[tuple[str, float, float, float]] = field(default_factory=list)  # (label, t, cx, cy)
    t0: float = 0.0
    w: pf.Win | None = None

    def mark(self, label: str, x: float | None = None, y: float | None = None) -> None:
        """Record a timestamp (seconds since recording start) and a window-relative point."""
        ww, hh = self.w.size
        cx = (x / ww) if x is not None else 0.5
        cy = (y / hh) if y is not None else 0.5
        self.marks.append((label, time.time() - self.t0, cx, cy))

    def m(self, label: str) -> tuple[float, float, float]:
        for lab, t, cx, cy in self.marks:
            if lab == label:
                return t, cx, cy
        raise KeyError(label)


def record(name: str, driver, source: str = "PiFrame", pre_roll: float = 0.8, post_roll: float = 0.8) -> tuple[Clip, Path]:
    """Run `driver(clip)` while Recordly records the PiFrame window."""
    start_recordly()
    w = pf.Win()
    clip = Clip(name=name, w=w)
    sel = node("select-screen") if source == "@screen" else node("select-window", source)
    if '"ok": true' not in sel:
        raise RuntimeError(f"select-window failed: {sel}")
    before = set(glob.glob(str(REC_DIR / "recording-*.mp4")))
    w.focus()
    print(node("start"))
    clip.t0 = time.time()
    time.sleep(pre_roll)
    driver(clip)
    time.sleep(post_roll)
    clip.mark("end")
    print(node("stop"))
    # wait for the muxed recording
    raw = None
    for _ in range(120):
        new = set(glob.glob(str(REC_DIR / "recording-*.mp4"))) - before
        if new:
            raw = Path(sorted(new)[-1])
            if Path(str(raw) + ".cursor.json").exists():
                break
        time.sleep(0.5)
    time.sleep(2.5)
    kill_recordly()
    if raw is None:
        raise RuntimeError("no recording produced")
    meta = {"name": name, "raw": str(raw), "marks": clip.marks}
    (OUT / f"{name}.marks.json").write_text(json.dumps(meta, indent=2))
    print("raw:", raw)
    return clip, raw


def click_offset_ms(raw: Path, clip: Clip) -> float:
    """Align driver time with recording time using the first recorded click."""
    samples = json.loads(Path(str(raw) + ".cursor.json").read_text())["samples"]
    clicks = [s["timeMs"] for s in samples if s.get("interactionType") == "click"]
    mine = [t for (lab, t, _, _) in clip.marks if lab.startswith("click")]
    if not clicks or not mine:
        return -400.0
    return clicks[0] - mine[0] * 1000


def export(name: str, raw: Path, zooms=(), trims=(), speeds=(), style: dict | None = None, crop=None) -> Path:
    """Write the .recordly project and render it with Recordly at source resolution."""
    editor = dict(STYLE)
    editor.update(style or {})
    editor["zoomRegions"] = [
        {"id": f"zoom-{i}", "startMs": int(s), "endMs": int(e), "depth": d,
         "focus": {"cx": round(cx, 4), "cy": round(cy, 4)}, "mode": "manual"}
        for i, (s, e, d, cx, cy) in enumerate(zooms, 1)
    ]
    editor["trimRegions"] = [{"id": f"trim-{i}", "startMs": int(s), "endMs": int(e)} for i, (s, e) in enumerate(trims, 1)]
    editor["speedRegions"] = [{"id": f"speed-{i}", "startMs": int(s), "endMs": int(e), "speed": sp}
                              for i, (s, e, sp) in enumerate(speeds, 1)]
    if crop:
        editor["cropRegion"] = crop
    project = {"version": 2, "projectId": f"piframe-{name}", "videoPath": str(raw).replace("\\", "/"), "editor": editor}
    proj = OUT / f"{name}.recordly"
    proj.write_text(json.dumps(project, indent=2))
    out = OUT / f"{name}.mp4"
    for f in (out, Path(str(out) + ".report.json")):
        f.unlink(missing_ok=True)
    kill_recordly()
    env = dict(os.environ, RECORDLY_SMOKE_EXPORT="1", RECORDLY_SMOKE_EXPORT_PROJECT=str(proj).replace("\\", "/"),
               RECORDLY_SMOKE_EXPORT_OUTPUT=str(out).replace("\\", "/"), RECORDLY_SMOKE_EXPORT_QUALITY="source",
               RECORDLY_SMOKE_EXPORT_FPS="60")
    subprocess.run([RECORDLY], cwd=str(Path(RECORDLY).parent), env=env, timeout=900,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    report = json.loads(Path(str(out) + ".report.json").read_text())
    if not report.get("success"):
        raise RuntimeError(f"export failed: {json.dumps(report)[:600]}")
    print("exported", out)
    return out
