"""PiFrame showcase driver helpers (Windows only).

Drives the real PiFrame desktop window with human-like mouse/keyboard input and
captures window screenshots for inspection. Coordinates are window-relative
logical pixels unless stated otherwise.
"""
from __future__ import annotations

import ctypes
import ctypes.wintypes as wt
import math
import random
import sys
import time
from pathlib import Path

import mss
from PIL import Image

user32 = ctypes.WinDLL("user32", use_last_error=True)
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:  # pragma: no cover
    user32.SetProcessDPIAware()

SHOTS = Path(r"C:\demo\shots")
SHOTS.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------- windows
def find_window(title_sub: str = "PiFrame", exe: str | None = "PiFrame.exe") -> int:
    found: list[int] = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def cb(hwnd, _):
        if not user32.IsWindowVisible(hwnd):
            return True
        n = user32.GetWindowTextLengthW(hwnd)
        buf = ctypes.create_unicode_buffer(n + 1)
        user32.GetWindowTextW(hwnd, buf, n + 1)
        if title_sub.lower() in buf.value.lower():
            if exe is None or _exe_of(hwnd).lower().endswith(exe.lower()):
                found.append(hwnd)
        return True

    user32.EnumWindows(cb, 0)
    if not found:
        raise RuntimeError(f"window '{title_sub}' not found")
    return found[0]


def _exe_of(hwnd: int) -> str:
    pid = wt.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    k32 = ctypes.windll.kernel32
    h = k32.OpenProcess(0x1000, False, pid.value)
    if not h:
        return ""
    buf = ctypes.create_unicode_buffer(1024)
    size = wt.DWORD(1024)
    k32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size))
    k32.CloseHandle(h)
    return buf.value


def client_rect(hwnd: int) -> tuple[int, int, int, int]:
    """Client area in screen physical pixels: (x, y, w, h)."""
    r = wt.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(r))
    pt = wt.POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(pt))
    return pt.x, pt.y, r.right - r.left, r.bottom - r.top


def dpi_scale(hwnd: int) -> float:
    try:
        return user32.GetDpiForWindow(hwnd) / 96.0
    except Exception:
        return 1.0


def place(hwnd: int, w: int, h: int, x: int | None = None, y: int | None = None) -> None:
    """Place the window with an outer size of w x h physical pixels (centered by default)."""
    sw, sh = user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
    user32.ShowWindow(hwnd, 9)  # SW_RESTORE
    x = (sw - w) // 2 if x is None else x
    y = (sh - h) // 2 if y is None else y
    user32.SetWindowPos(hwnd, 0, x, y, w, h, 0x0040)


def focus(hwnd: int) -> None:
    # Alt tap trick lets SetForegroundWindow succeed from a background process.
    for _ in range(10):
        if user32.GetForegroundWindow() == hwnd:
            return
        user32.keybd_event(0x12, 0, 0, 0)
        user32.keybd_event(0x12, 0, 2, 0)
        user32.SetForegroundWindow(hwnd)
        time.sleep(0.2)
    raise RuntimeError('could not focus window')


# ---------------------------------------------------------------- capture
def shot(hwnd: int, name: str = "shot") -> Path:
    """Capture the client area with PrintWindow (works while occluded)."""
    gdi = ctypes.windll.gdi32
    _, _, w, h = client_rect(hwnd)
    hdc = user32.GetDC(hwnd)
    mdc = gdi.CreateCompatibleDC(hdc)
    bmp = gdi.CreateCompatibleBitmap(hdc, w, h)
    gdi.SelectObject(mdc, bmp)
    user32.PrintWindow(hwnd, mdc, 3)  # PW_CLIENTONLY | PW_RENDERFULLCONTENT

    class BIH(ctypes.Structure):
        _fields_ = [("biSize", wt.DWORD), ("biWidth", wt.LONG), ("biHeight", wt.LONG),
                    ("biPlanes", wt.WORD), ("biBitCount", wt.WORD), ("biCompression", wt.DWORD),
                    ("biSizeImage", wt.DWORD), ("a", wt.LONG), ("b", wt.LONG), ("c", wt.DWORD), ("d", wt.DWORD)]

    bih = BIH(ctypes.sizeof(BIH), w, -h, 1, 32, 0, 0, 0, 0, 0, 0)
    buf = ctypes.create_string_buffer(w * h * 4)
    gdi.GetDIBits(mdc, bmp, 0, h, buf, ctypes.byref(bih), 0)
    gdi.DeleteObject(bmp); gdi.DeleteDC(mdc); user32.ReleaseDC(hwnd, hdc)
    out = SHOTS / f"{name}.png"
    im = Image.frombuffer("RGBA", (w, h), buf, "raw", "BGRA", 0, 1).convert("RGB")
    if all(lo == hi for lo, hi in im.getextrema()):
        # PrintWindow can return a blank surface for Flutter; grab the screen instead.
        x, y, w, h = client_rect(hwnd)
        with mss.MSS() if hasattr(mss, "MSS") else mss.mss() as s:
            g = s.grab({"left": x, "top": y, "width": w, "height": h})
        im = Image.frombytes("RGB", g.size, g.rgb)
    im.save(out)
    return out


# ---------------------------------------------------------------- mouse
INPUT_MOUSE, INPUT_KEYBOARD = 0, 1


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wt.LONG), ("dy", wt.LONG), ("mouseData", wt.DWORD),
                ("dwFlags", wt.DWORD), ("time", wt.DWORD), ("dwExtraInfo", ctypes.c_size_t)]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wt.WORD), ("wScan", wt.WORD), ("dwFlags", wt.DWORD),
                ("time", wt.DWORD), ("dwExtraInfo", ctypes.c_size_t)]


class _U(ctypes.Union):
    _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT), ("pad", ctypes.c_byte * 32)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wt.DWORD), ("u", _U)]


def _send(*inputs: INPUT) -> None:
    arr = (INPUT * len(inputs))(*inputs)
    user32.SendInput(len(inputs), arr, ctypes.sizeof(INPUT))


def _mouse(flags: int, data: int = 0) -> None:
    i = INPUT(type=INPUT_MOUSE)
    i.u.mi = MOUSEINPUT(0, 0, data, flags, 0, 0)
    _send(i)


def cursor() -> tuple[int, int]:
    p = wt.POINT()
    user32.GetCursorPos(ctypes.byref(p))
    return p.x, p.y


def _ease(t: float) -> float:
    # easeInOutCubic
    return 4 * t * t * t if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def move_abs(x: int, y: int, dur: float = 0.55) -> None:
    sx, sy = cursor()
    dist = math.hypot(x - sx, y - sy)
    if dist < 2:
        user32.SetCursorPos(int(x), int(y))
        return
    dur = max(0.18, min(dur, 0.25 + dist / 1800))
    steps = max(12, int(dur * 120))
    # slight arc for a natural path
    nx, ny = -(y - sy) / dist, (x - sx) / dist
    bow = random.uniform(-0.06, 0.06) * dist
    for k in range(1, steps + 1):
        t = _ease(k / steps)
        arc = math.sin(math.pi * t) * bow
        user32.SetCursorPos(int(sx + (x - sx) * t + nx * arc), int(sy + (y - sy) * t + ny * arc))
        time.sleep(dur / steps)


class Win:
    """Window-relative driver. Coordinates are logical (DIP) pixels."""

    def __init__(self, hwnd: int | None = None):
        self.hwnd = hwnd or find_window()
        self.s = dpi_scale(self.hwnd)

    # coordinate helpers
    def abs(self, x: float, y: float) -> tuple[int, int]:
        cx, cy, _, _ = client_rect(self.hwnd)
        return int(cx + x * self.s), int(cy + y * self.s)

    @property
    def size(self) -> tuple[float, float]:
        _, _, w, h = client_rect(self.hwnd)
        return w / self.s, h / self.s

    def move(self, x: float, y: float, dur: float = 0.55) -> None:
        move_abs(*self.abs(x, y), dur=dur)

    def click(self, x: float, y: float, dur: float = 0.55, pause: float = 0.12, right=False) -> None:
        self.move(x, y, dur)
        time.sleep(pause)
        down, up = (0x0008, 0x0010) if right else (0x0002, 0x0004)
        _mouse(down)
        time.sleep(0.07)
        _mouse(up)

    def dclick(self, x: float, y: float, dur: float = 0.55) -> None:
        self.move(x, y, dur)
        time.sleep(0.1)
        for _ in range(2):
            _mouse(0x0002); time.sleep(0.04); _mouse(0x0004); time.sleep(0.06)

    def drag(self, x0: float, y0: float, x1: float, y1: float, dur: float = 0.9) -> None:
        self.move(x0, y0)
        time.sleep(0.12)
        _mouse(0x0002)
        time.sleep(0.12)
        self.move(x1, y1, dur)
        time.sleep(0.12)
        _mouse(0x0004)

    def scroll(self, x: float, y: float, clicks: int, dur: float = 0.4) -> None:
        self.move(x, y, dur)
        for _ in range(abs(clicks)):
            _mouse(0x0800, (120 if clicks > 0 else -120) & 0xFFFFFFFF)
            time.sleep(0.05)

    def shot(self, name: str = "shot") -> Path:
        return shot(self.hwnd, name)

    def focus(self) -> None:
        focus(self.hwnd)


# ---------------------------------------------------------------- keyboard
VK = {"enter": 0x0D, "esc": 0x1B, "tab": 0x09, "back": 0x08, "space": 0x20, "ctrl": 0x11,
      "shift": 0x10, "alt": 0x12, "up": 0x26, "down": 0x28, "left": 0x25, "right": 0x27,
      "del": 0x2E, "home": 0x24, "end": 0x23, "f5": 0x74}


def _key(vk: int, up: bool = False) -> None:
    i = INPUT(type=INPUT_KEYBOARD)
    scan = user32.MapVirtualKeyW(vk, 0)
    flags = 0x0002 if up else 0
    if vk in (0x25, 0x26, 0x27, 0x28, 0x2E, 0x24, 0x23, 0x21, 0x22):
        flags |= 0x0001  # KEYEVENTF_EXTENDEDKEY
    i.u.ki = KEYBDINPUT(vk, scan, flags, 0, 0)
    _send(i)


def key(*names: str) -> None:
    """Press a chord, e.g. key('ctrl', 'k')."""
    vks = [VK[n] if n in VK else ord(n.upper()) for n in names]
    for v in vks:
        _key(v)
        time.sleep(0.03)
    for v in reversed(vks):
        _key(v, up=True)
        time.sleep(0.02)


def type_vk(text: str, cps: float = 14.0) -> None:
    """Type ASCII text with virtual-key events (for widgets that ignore unicode input)."""
    for ch in text:
        r = user32.VkKeyScanW(ord(ch))
        vk, shift = r & 0xFF, (r >> 8) & 1
        if shift:
            _key(0x10)
        _key(vk); _key(vk, up=True)
        if shift:
            _key(0x10, up=True)
        time.sleep(random.uniform(0.5, 1.5) / cps)


def type_text(text: str, cps: float = 22.0) -> None:
    """Type unicode text with human jitter."""
    for ch in text:
        if ch == "\n":
            key("shift", "enter")
        else:
            for up in (False, True):
                i = INPUT(type=INPUT_KEYBOARD)
                i.u.ki = KEYBDINPUT(0, ord(ch), 0x0004 | (0x0002 if up else 0), 0, 0)
                _send(i)
        base = 1.0 / cps
        time.sleep(random.uniform(base * 0.5, base * 1.6) + (0.08 if ch in " ,." and random.random() < 0.25 else 0))


if __name__ == "__main__":
    w = Win()
    print("hwnd", w.hwnd, "scale", w.s, "size", w.size, "rect", client_rect(w.hwnd))
    if len(sys.argv) > 1:
        print(w.shot(sys.argv[1]))
