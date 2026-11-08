"""Reset demo state, launch PiFrame and place the window (2400x1350 physical)."""
import subprocess as _sp
_out = _sp.run(['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File','display.ps1'],capture_output=True,text=True).stdout
if 'scale=125%' not in _out or '2560x1440' not in _out:
    _sp.run(['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File','display.ps1','-Width','2560','-Height','1440'])
    _sp.run(['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File','display.ps1','-ScalePercent','125'])
import subprocess, sys, time, pf
if '--no-reset' not in sys.argv:
    print(subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'reset-demo.ps1'],
                         capture_output=True, text=True).stdout.strip())
else:
    subprocess.run(['cmd', '/c', r'C:\demo\launch-piframe.cmd'])
for _ in range(60):
    try:
        h = pf.find_window()
        break
    except RuntimeError:
        time.sleep(0.5)
time.sleep(2.5)
pf.place(h, 2400, 1350)
time.sleep(1.0)
pf.focus(h)
print('ready', pf.client_rect(h))
