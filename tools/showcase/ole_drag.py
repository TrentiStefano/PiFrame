"""Drag a real file into a window with OLE drag & drop, without a visible source window.

The shell provides the IDataObject (CF_HDROP) for the file; a tiny Python
IDropSource drives DoDragDrop while another thread moves the mouse.
Usage (library): drag_file(path, (x0, y0), (x1, y1), duration)
"""
import ctypes
import threading
import time

import pythoncom
import win32api
import win32con
from win32com.server.util import wrap
from win32com.shell import shell

import pf

DRAGDROP_S_DROP = 0x00040100
DRAGDROP_S_CANCEL = 0x00040101
DRAGDROP_S_USEDEFAULTCURSORS = 0x00040102


class DropSource:
    _com_interfaces_ = [pythoncom.IID_IDropSource]
    _public_methods_ = ['QueryContinueDrag', 'GiveFeedback']

    def QueryContinueDrag(self, escape_pressed, key_state):
        if escape_pressed:
            return DRAGDROP_S_CANCEL
        if not (key_state & win32con.MK_LBUTTON):
            return DRAGDROP_S_DROP
        return 0  # S_OK, keep dragging

    def GiveFeedback(self, effect):
        return DRAGDROP_S_USEDEFAULTCURSORS


def _data_object(path: str):
    desktop = shell.SHGetDesktopFolder()
    _, pidl, _ = desktop.ParseDisplayName(0, None, path)
    parent_path, name = path.rsplit('\\', 1)
    _, parent_pidl, _ = desktop.ParseDisplayName(0, None, parent_path)
    parent = desktop.BindToObject(parent_pidl, None, shell.IID_IShellFolder)
    _, child, _ = parent.ParseDisplayName(0, None, name)
    return parent.GetUIObjectOf(0, [child], pythoncom.IID_IDataObject, 0)[1]


def drag_file(path: str, start: tuple[int, int], end: tuple[int, int], duration: float = 1.3) -> None:
    pythoncom.OleInitialize()
    data = _data_object(path)
    source = wrap(DropSource(), pythoncom.IID_IDropSource)

    pf.move_abs(*start, dur=0.35)
    time.sleep(0.15)
    pf._mouse(0x0002)  # left down

    def mover():
        time.sleep(0.25)
        sx, sy = start
        pf.move_abs(sx + 12, sy - 8, dur=0.12)
        pf.move_abs(*end, dur=duration)
        time.sleep(0.6)
        pf._mouse(0x0004)  # left up -> drop

    t = threading.Thread(target=mover, daemon=True)
    t.start()
    try:
        pythoncom.DoDragDrop(data, source, 1)  # DROPEFFECT_COPY
    except pythoncom.com_error:
        pass
    t.join()


if __name__ == '__main__':
    w = pf.Win()
    w.focus()
    drag_file(r'C:\demo\assets\ground-track.png', w.abs(1600, 700), w.abs(1220, 640))
    time.sleep(1.5)
    print(w.shot('ole'))
