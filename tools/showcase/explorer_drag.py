"""Open an Explorer window on C:\demo\assets next to PiFrame and locate a file item."""
import subprocess, time, sys
from pywinauto import Desktop
import pf

def open_explorer(x=1990, y=760, w=540, h=430):
    subprocess.Popen(['explorer.exe', r'C:\demo\assets'])
    for _ in range(40):
        time.sleep(0.4)
        try:
            win = Desktop(backend='uia').window(title_re='assets.*', class_name='CabinetWClass')
            if win.exists():
                break
        except Exception:
            pass
    h_ = win.handle
    pf.user32.ShowWindow(h_, 9)
    pf.user32.SetWindowPos(h_, 0, x, y, w, h, 0x0040)
    time.sleep(0.8)
    return win

def item_center(win, name='ground-track'):
    it = win.child_window(title_re=name + '.*', control_type='ListItem').wrapper_object()
    r = it.rectangle()
    return (r.left + 40, (r.top + r.bottom) // 2)

def close(win):
    try:
        win.close()
    except Exception:
        pass

if __name__ == '__main__':
    w = open_explorer()
    print(item_center(w))
