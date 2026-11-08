import subprocess, time, pf
from PIL import Image
def white(name):
    p = pf.shot(pf.find_window(), name); ex = Image.open(p).getextrema(); return all(a>240 for a,b in ex)
for i in range(3):
    subprocess.run(['powershell','-NoProfile','-Command',"Get-Process PiFrame -EA 0 | ? { $_.Path -like 'C:\demo\*' } | Stop-Process -Force"])
    time.sleep(1.5)
    subprocess.run(['cmd','/c',r'C:\demo\launch-piframe.cmd'])
    for _ in range(40):
        try: h = pf.find_window(); break
        except RuntimeError: time.sleep(0.5)
    time.sleep(4)
    pf.focus(h); time.sleep(0.5)
    a = white(f'wt{i}a')
    pf.place(h, 2400, 1350); time.sleep(2)
    b = white(f'wt{i}b')
    print(i, 'before place white', a, 'after place white', b, pf.client_rect(h))
