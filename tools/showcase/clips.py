"""Clip drivers for the PiFrame showcase. Coordinates are logical px in a
1907x1073 PiFrame window (2400x1350 physical at 125 % scale).

usage: python clips.py <clip> [--dry]      (dry = run driver without recording)
"""
from __future__ import annotations

import subprocess
import sys
import time

import pf
import rec

S = time.sleep
PY = sys.executable


def relaunch(reset=True):
    args = [PY, '-W', 'ignore', 'launch.py'] + ([] if reset else ['--no-reset'])
    print(subprocess.run(args, capture_output=True, text=True).stdout.strip())
    S(3)


def open_seed_session(w: pf.Win, which='explain'):
    """Expand orbit-api in the sidebar and open a seed session."""
    w.click(259, 239, dur=0.2)  # expand folder chevron
    S(1.2)
    w.click(133, 354 if which == 'explain' else 295, dur=0.2)
    S(2.5)


def new_session(w: pf.Win):
    w.click(242, 239, dur=0.3)
    S(3)


# ------------------------------------------------------------------ 13
def setup_13(w):
    open_seed_session(w)
    S(5)
    w.move(1180, 760, dur=0.2)


def drive_13(c: rec.Clip):
    w = c.w
    S(0.6)
    c.mark('click-think', 1028, 1023); w.click(1028, 1023)
    S(1.0)
    w.move(1029, 875, dur=0.5); S(0.25)
    c.mark('click-high', 1029, 911); w.click(1029, 911, dur=0.35)
    S(0.9)
    c.mark('click-ctx', 1104, 1023); w.click(1104, 1023)
    S(1.1)
    c.mark('click-dd', 952, 528); w.click(952, 528)
    S(0.8)
    c.mark('click-custom', 816, 433); w.click(816, 433)
    S(1.0)
    c.mark('drag-window', 1096, 568)
    w.drag(1096, 568, 903, 568, dur=1.3)
    S(1.0)
    c.mark('click-close', 1089, 650); w.click(1089, 650)
    S(0.9)
    c.mark('click-workarea', 1754, 25); w.click(1754, 25)
    S(1.4)
    c.mark('drag-compact', 1645, 538)
    w.drag(1645, 538, 1716, 538, dur=1.0)
    S(1.6)
    c.mark('click-x', 1876, 32); w.click(1876, 32)
    S(0.8)
    w.move(1180, 760, dur=0.6)


def zooms_13(c, off):
    t = lambda lab: c.m(lab)[0] * 1000 + off
    return [
        (t('click-think') - 200, t('click-high') + 700, 1, 0.55, 0.80),
        (t('click-dd') - 300, t('click-close') + 200, 1, 0.52, 0.52),
        (t('click-workarea') + 400, t('click-x') - 200, 1, 0.80, 0.45),
    ]


# ------------------------------------------------------------------ 07
def setup_seed(w):
    open_seed_session(w)
    S(5)
    w.move(1180, 760, dur=0.2)


def drive_07(c: rec.Clip):
    w = c.w
    S(0.8)
    c.mark('click-split1', 804, 562); w.drag(804, 562, 690, 562, dur=1.0)
    S(0.6)
    c.mark('drag-split2', 1516, 562); w.drag(1516, 562, 1420, 562, dur=0.9)
    S(0.7)
    c.mark('click-collapse', 249, 84); w.click(249, 84)
    S(1.1)
    c.mark('click-browser', 1569, 79); w.click(1569, 79)
    S(2.0)
    c.mark('click-term', 393, 79); w.click(393, 79)
    S(1.6)
    c.mark('click-term-in', 286, 952); w.click(286, 952)
    S(0.4)
    pf.type_vk('git branch', cps=16); S(0.3); pf.key('enter')
    S(1.6)
    pf.type_vk('ls src', cps=16); S(0.3); pf.key('enter')
    S(2.6)
    c.mark('click-git', 1459, 79); w.click(1459, 79)
    S(1.2)
    c.mark('click-panes', 1674, 25); w.click(1674, 25)
    S(1.0)
    c.mark('click-repo-off', 1600, 88); w.click(1600, 88, dur=0.4)
    S(1.4)
    w.click(1674, 25, dur=0.5)
    S(0.9)
    c.mark('click-repo-on', 1600, 88); w.click(1600, 88, dur=0.4)
    S(1.2)
    c.mark('click-expand', 21, 63); w.click(21, 63)
    S(1.4)
    w.move(1100, 760, dur=0.6)


def zooms_07(c, off):
    t = lambda lab: c.m(lab)[0] * 1000 + off
    return [
        (t('click-term-in') - 300, t('click-git') - 300, 1, 0.22, 0.78),
        (t('click-panes') - 200, t('click-repo-on') + 700, 1, 0.80, 0.18),
    ]


# ------------------------------------------------------------------ 10
def setup_10(w):
    setup_seed(w)
    w.click(249, 84, dur=0.2)           # collapse sessions sidebar
    S(1.0)
    w.drag(636, 562, 880, 562, dur=0.4)  # widen repository pane
    S(1.0)
    w.move(560, 600, dur=0.2)


def drive_10(c: rec.Clip):
    w = c.w
    S(0.8)
    c.mark('click-search', 170, 152); w.click(170, 152)
    S(0.3)
    pf.type_text('orbit', cps=9)
    S(1.0)
    c.mark('click-file', 138, 243); w.click(138, 243)
    S(1.6)
    c.mark('drag-select', 279, 759); w.drag(279, 759, 300, 816, dur=0.9)
    S(0.6)
    c.mark('click-ctx', 420, 790); w.click(420, 790, right=True)
    S(0.9)
    c.mark('click-add', 474, 949); w.click(474, 949, dur=0.4)
    S(1.2)
    c.mark('click-composer', 1200, 1000); w.click(1200, 1000, dur=0.5)
    pf.key('ctrl', 'end'); pf.key('enter'); pf.key('enter')
    pf.type_text("Why does this use Kepler's third law? Answer in two sentences.", cps=26)
    S(0.4)
    c.mark('send'); pf.key('ctrl', 'enter')
    S(9.0)
    c.mark('click-clear', 240, 152); w.click(240, 152)
    S(0.8)
    c.mark('click-readme', 125, 523); w.click(125, 523)
    S(2.4)
    w.move(560, 700, dur=0.6)


def zooms_10(c, off):
    t = lambda lab: c.m(lab)[0] * 1000 + off
    return [
        (t('click-search') - 300, t('click-file') + 400, 1, 0.22, 0.30),
        (t('drag-select') - 300, t('click-add') + 300, 1, 0.24, 0.70),
        (t('click-composer') - 200, t('send') + 600, 1, 0.62, 0.86),
    ]


# ------------------------------------------------------------------ 15
def setup_15(w):
    pf.place(w.hwnd, 2400, 1350, x=160)  # free a strip on the left for the drag source
    S(1.0)
    new_session(w)
    S(2.0)
    w.move(1180, 640, dur=0.2)


def drive_15(c: rec.Clip):
    import explorer_drag as ed
    w = c.w
    S(0.8)
    c.mark('click-composer', 1047, 962); w.click(1047, 962)
    S(0.3)
    pf.type_text('/', cps=10); S(1.4)
    pf.type_text('mo', cps=8); S(1.2)
    pf.key('esc'); S(0.2); pf.key('ctrl', 'a'); pf.key('back'); S(0.4)
    pf.type_text('Add a GET /satellites endpoint like @cat', cps=20); S(1.0)
    c.mark('mention'); pf.key('tab'); S(0.6)
    pf.type_text(' and document it in ', cps=20); S(0.3)
    c.mark('click-addfile', 780, 355); w.click(780, 355, dur=0.7)
    S(1.2)
    c.mark('open-explorer')
    win = ed.open_explorer(x=-230, y=820, w=380, h=420)  # off the recorded area
    x0, y0 = ed.item_center(win)
    pf.move_abs(x0, y0, 0.5); S(0.25)
    pf._mouse(0x0002); S(0.25)
    x1, y1 = w.abs(1220, 640)
    pf.move_abs(x0 - 60, y0 - 10, 0.2)
    c.mark('drag-image', 1220, 640)
    pf.move_abs(x1, y1, 1.3); S(0.7)
    pf._mouse(0x0004)
    S(0.4)
    ed.close(win)
    w.focus()
    S(1.2)
    c.mark('click-expand', 1396, 1023); w.click(1396, 1023)
    S(1.6)
    c.mark('click-collapse', 1396, 1023); w.click(1396, 1023, dur=0.4)
    S(1.2)
    w.move(1180, 640, dur=0.6)


def zooms_15(c, off):
    t = lambda lab: c.m(lab)[0] * 1000 + off
    return [
        (t('click-composer') - 200, t('click-addfile') - 300, 1, 0.62, 0.84),
        (t('click-expand') - 200, t('click-collapse') + 400, 1, 0.62, 0.78),
    ]


# ------------------------------------------------------------------ 02
AGENTS_PROMPT = ("Spawn three general-purpose agents in parallel with the Agent tool, in the background: "
                 "one adds a per-client rate limiter to /passes, one adds a GET /satellites endpoint that "
                 "lists the catalog, one adds expiry tests for TtlCache. Wait for all three, then summarize "
                 "the changes in three bullets.")


def setup_02(w):
    new_session(w)
    S(2.0)
    w.move(1180, 640, dur=0.2)


def _wait_idle(w=None, timeout=180, min_wait=12):
    """Wait until the newest PiFrame-created session ends its turn (final assistant stop)."""
    import glob, json, os, time as _t
    t0 = _t.time()
    S(min_wait)
    while _t.time() - t0 < timeout:
        files = sorted(glob.glob('C:/demo/home/.pi/agent/sessions/*/*_s_*.jsonl'), key=os.path.getmtime)
        if files:
            f = files[-1]
            try:
                last = json.loads(open(f, encoding='utf-8').read().strip().splitlines()[-1])
                msg = last.get('message', {})
                idle = _t.time() - os.path.getmtime(f)
                if msg.get('role') == 'assistant' and msg.get('stopReason') == 'stop' and idle > 3:
                    return True
            except Exception:
                pass
        S(1)
    return False


def drive_02(c: rec.Clip):
    w = c.w
    S(0.8)
    c.mark('click-composer', 1047, 962); w.click(1047, 962)
    S(0.3)
    pf.type_text(AGENTS_PROMPT, cps=45)
    S(0.6)
    c.mark('send'); pf.key('ctrl', 'enter')
    _wait_idle(w)
    c.mark('done')
    S(4.0)
    w.move(1300, 500, dur=0.8)
    S(1.0)


def zooms_02(c, off):
    t = lambda lab: c.m(lab)[0] * 1000 + off
    return [
        (t('click-composer') - 200, t('send') + 300, 1, 0.55, 0.82),
        (t('send') + 9000, t('done') - 1500, 1, 0.80, 0.30),
    ]


def extra_02(c, off):
    t = lambda lab: c.m(lab)[0] * 1000 + off
    s0, s1 = t('send') + 2500, t('done') - 2500
    return {'speeds': [(s0, s1, 2)]} if s1 > s0 + 2000 else {}


# ------------------------------------------------------------------ 08
def setup_noop(w):
    w.move(700, 760, dur=0.2)


def drive_08(c: rec.Clip):
    w = c.w
    S(1.0)
    c.mark('click-review', 1510, 1023); w.click(1510, 1023)
    S(1.6)
    c.mark('click-passes', 1040, 201); w.click(1040, 201)
    S(1.6)
    w.scroll(1500, 700, -4); S(1.4)
    c.mark('click-split', 1814, 79); w.click(1814, 79)
    S(2.0)
    w.scroll(1500, 700, -4); S(1.6)
    w.scroll(1500, 700, 8); S(0.6)
    c.mark('click-collapse', 1040, 201); w.click(1040, 201)
    S(0.8)
    c.mark('click-sat', 1070, 238); w.click(1070, 238)
    S(2.4)
    w.move(1300, 760, dur=0.6)
    S(0.6)


def zooms_08(c, off):
    t = lambda lab: c.m(lab)[0] * 1000 + off
    return [
        (t('click-passes') + 400, t('click-split') - 300, 1, 0.74, 0.45),
        (t('click-split') + 600, t('click-collapse') - 200, 1, 0.70, 0.50),
    ]


# ------------------------------------------------------------------ 09
def drive_09(c: rec.Clip):
    w = c.w
    S(1.0)
    c.mark('click-stage1', 1844, 300); w.click(1844, 300)
    S(0.9)
    c.mark('click-stage2', 1844, 408); w.click(1844, 408)
    S(0.9)
    c.mark('click-stage3', 1844, 520); w.click(1844, 520)
    S(1.0)
    c.mark('click-commit', 1834, 1039); w.click(1834, 1039)
    S(1.0)
    pf.key('ctrl', 'a'); pf.key('back')
    pf.type_text('feat: rate limit /passes and validate coordinates', cps=24)
    S(0.6)
    c.mark('click-commit-ok', 1163, 635); w.click(1163, 635)
    S(2.2)
    c.mark('click-branch', 1857, 116); w.click(1857, 116)
    S(1.2)
    pf.type_text('sat', cps=8)
    S(0.9)
    c.mark('enter'); pf.key('enter')
    S(1.6)
    c.mark('click-stash', 1168, 574); w.click(1168, 574)
    S(3.0)
    w.move(1500, 700, dur=0.6)


def zooms_09(c, off):
    t = lambda lab: c.m(lab)[0] * 1000 + off
    return [
        (t('click-stage1') - 300, t('click-commit') - 200, 1, 0.84, 0.30),
        (t('click-commit') + 300, t('click-commit-ok') + 500, 1, 0.55, 0.50),
        (t('click-branch') + 300, t('click-stash') + 900, 1, 0.55, 0.40),
    ]


# ------------------------------------------------------------------ 17
def drive_17(c: rec.Clip):
    w = c.w
    S(1.0)
    c.mark('click-light', 1706, 25); w.click(1706, 25)
    S(1.8)
    c.mark('click-settings', 1730, 25); w.click(1730, 25)
    S(1.4)
    c.mark('click-appearance', 331, 130); w.click(331, 130)
    S(1.3)
    c.mark('click-editor', 625, 694); w.click(625, 694)
    S(1.6)
    c.mark('click-accent', 949, 656); w.click(949, 656)
    S(1.0)
    c.mark('click-orange', 1094, 564); w.click(1094, 564)
    S(0.8)
    c.mark('click-apply', 1068, 658); w.click(1068, 658)
    S(1.6)
    c.mark('click-save', 1260, 850); w.click(1260, 850)
    S(1.6)
    c.mark('click-back', 45, 87); w.click(45, 87)
    S(1.8)
    c.mark('click-dark', 1706, 25); w.click(1706, 25)
    S(2.0)
    w.move(1100, 700, dur=0.6)


def zooms_17(c, off):
    t = lambda lab: c.m(lab)[0] * 1000 + off
    return [
        (t('click-editor') + 500, t('click-save') + 300, 1, 0.50, 0.48),
    ]


# ------------------------------------------------------------------ 01
DISCONNECT_PROMPT = ("Walk me through every file in src, one short section per file: what it does and one "
                     "concrete improvement. Use a heading per file. Do not modify files.")
_BACKDROP = None


def setup_01(w):
    global _BACKDROP
    _BACKDROP = subprocess.Popen([PY, 'backdrop.py', '#e8e6e1'])
    S(1.5)
    w.focus()
    new_session(w)
    S(2.0)
    w.move(1180, 640, dur=0.2)


def drive_01(c: rec.Clip):
    w = c.w
    S(0.8)
    c.mark('click-composer', 1047, 962); w.click(1047, 962)
    S(0.3)
    pf.type_text(DISCONNECT_PROMPT, cps=45)
    S(0.5)
    c.mark('send'); pf.key('ctrl', 'enter')
    S(7.0)
    c.mark('click-close', 1876, 25); w.click(1876, 25)
    S(3.5)
    c.mark('relaunch')
    subprocess.run(['cmd', '/c', r'C:\demo\launch-piframe.cmd'])
    for _ in range(60):
        try:
            h = pf.find_window()
            break
        except RuntimeError:
            S(0.3)
    S(4.5)
    w2 = pf.Win(h)
    c.w = w2
    w2.focus()
    c.mark('click-quick', 1333, 538); w2.click(1333, 538)
    S(7.0)
    w2.move(1200, 700, dur=0.6)
    S(1.0)


def zooms_01(c, off):
    return []


CLIPS = {
    '01-disconnect-safe': (setup_01, drive_01, zooms_01),
    '17-themes': (setup_seed, drive_17, zooms_17),
    '09-git-desk': (setup_noop, drive_09, zooms_09),
    '08-review-diff': (setup_noop, drive_08, zooms_08),
    '02-agents-tree': (setup_02, drive_02, zooms_02, extra_02),
    '15-composer': (setup_15, drive_15, zooms_15),
    '10-repo-add-to-chat': (setup_10, drive_10, zooms_10),
    '07-bento-workspace': (setup_seed, drive_07, zooms_07),
    '13-model-context': (setup_13, drive_13, zooms_13),
}

if __name__ == '__main__':
    name = sys.argv[1]
    dry = '--dry' in sys.argv
    setup, drive, zooms = CLIPS[name][:3]
    if '--no-launch' not in sys.argv:
        relaunch()
    w = pf.Win()
    w.focus()
    setup(w)
    if dry:
        c = rec.Clip(name=name, w=w, t0=time.time())
        drive(c)
        print(c.marks)
        sys.exit(0)
    screen = name.startswith('01-')
    crop = None
    if screen:
        sw, sh = pf.user32.GetSystemMetrics(0), pf.user32.GetSystemMetrics(1)
        import ctypes.wintypes as _wt, ctypes as _ct
        r = _wt.RECT(); pf.user32.GetWindowRect(w.hwnd, _ct.byref(r))
        crop = {'x': round(r.left / sw, 5), 'y': round(r.top / sh, 5),
                'width': round((r.right - r.left) / sw, 5), 'height': round((r.bottom - r.top) / sh, 5)}
        print('crop', crop)
    clip, raw = rec.record(name, drive, source='@screen' if screen else 'PiFrame')
    if screen and _BACKDROP:
        _BACKDROP.kill()
    off = rec.click_offset_ms(raw, clip)
    print('offset ms', off)
    extra = CLIPS[name][3](clip, off) if len(CLIPS[name]) > 3 else {}
    rec.export(name, raw, zooms=zooms(clip, off), crop=crop, **extra)
