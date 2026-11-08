"""Clip 01 (disconnect-safe): two window recordings around a real app close/reopen.

A: send a long prompt, let it stream, close the PiFrame window.
B: relaunch PiFrame, reopen the session: the daemon kept the agent working.
The two exports are joined later with a neutral title card (post.py).
"""
import subprocess
import sys
import time

import clips
import pf
import rec

S = time.sleep
PROMPT = clips.DISCONNECT_PROMPT


def drive_a(c: rec.Clip):
    w = c.w
    S(0.8)
    c.mark('click-composer', 1047, 962); w.click(1047, 962)
    S(0.3)
    pf.type_text(PROMPT, cps=45)
    S(0.5)
    c.mark('send'); pf.key('ctrl', 'enter')
    S(7.0)
    c.mark('hover-close', 1876, 25); w.move(1876, 25, dur=0.8)
    S(0.6)


def drive_b(c: rec.Clip):
    w = c.w
    S(1.2)
    c.mark('click-folder', 259, 239); w.click(259, 239)
    S(1.2)
    c.mark('click-session', 133, 295); w.click(133, 295)
    S(8.0)
    w.move(1200, 700, dur=0.6)
    S(0.8)


def main():
    clips.relaunch()
    w = pf.Win()
    w.focus()
    clips.new_session(w)
    S(2.0)
    w.move(1180, 640, dur=0.2)
    ca, raw_a = rec.record('01a-disconnect', drive_a, post_roll=0.3)
    # Close the real window while the agent is still streaming.
    w = pf.Win()
    w.focus()
    w.click(1876, 25, dur=0.2)
    t_closed = time.time()
    S(3.0)
    subprocess.Popen(['cmd', '/c', r'C:\demo\launch-piframe.cmd'])
    for _ in range(80):
        try:
            h = pf.find_window()
            break
        except RuntimeError:
            S(0.25)
    S(1.0)
    pf.place(h, 2400, 1350)
    w = pf.Win(h)
    w.focus()
    w.move(900, 640, dur=0.2)
    cb, raw_b = rec.record('01b-reopen', drive_b, pre_roll=0.5)
    print('reopened after', round(time.time() - t_closed, 1), 's')
    off_a = rec.click_offset_ms(raw_a, ca)
    off_b = rec.click_offset_ms(raw_b, cb)
    rec.export('01a-disconnect', raw_a)
    t = lambda c, lab, off: c.m(lab)[0] * 1000 + off
    rec.export('01b-reopen', raw_b,
               zooms=[(t(cb, 'click-session', off_b) + 1500, t(cb, 'click-session', off_b) + 7000, 1, 0.62, 0.50)])


if __name__ == '__main__':
    main()
