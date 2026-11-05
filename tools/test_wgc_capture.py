import subprocess
import time
import json
import os
import signal

wgc_path = r"C:\Program Files\Recordly\resources\app.asar.unpacked\electron\native\bin\win32-x64\wgc-capture.exe"
piframe_path = r"C:\Personale\Repos\PiFrame\PiFrame\apps\pi_frame\build\windows\x64\runner\Release\PiFrame.exe"

os.makedirs("scratch", exist_ok=True)
out_mp4 = os.path.abspath("scratch/test_capture.mp4")
if os.path.exists(out_mp4):
    os.remove(out_mp4)

print("1. Launching second instance of PiFrame...")
app_proc = subprocess.Popen([piframe_path])
print(f"Launched PiFrame instance PID: {app_proc.pid}")

# Wait for window to be created and get HWND
hwnd = 0
for _ in range(20):
    time.sleep(0.5)
    ps_cmd = f"(Get-Process -Id {app_proc.pid} -ErrorAction SilentlyContinue).MainWindowHandle"
    res = subprocess.run(["powershell", "-Command", ps_cmd], stdout=subprocess.PIPE, text=True)
    val = res.stdout.strip()
    if val and val != "0":
        hwnd = int(val)
        break

if hwnd == 0:
    print("Could not find HWND for new PiFrame instance!")
    app_proc.kill()
    exit(1)

print(f"2. Found window HWND: {hwnd} (0x{hwnd:X})")

# Launch wgc-capture.exe
config = {
    "windowHandle": hwnd,
    "outputPath": out_mp4.replace("\\", "/"),
    "fps": 60
}
config_json = json.dumps(config)
print(f"3. Starting wgc-capture with config: {config_json}")

capture_proc = subprocess.Popen(
    [wgc_path, config_json],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

# Record for 4 seconds
print("4. Recording window for 4 seconds...")
time.sleep(4.0)

# Stop capture
print("5. Sending 'stop' to wgc-capture...")
try:
    capture_proc.stdin.write("stop\n")
    capture_proc.stdin.flush()
except Exception as e:
    print("stdin error:", e)

capture_proc.wait(timeout=5)
print("Capture stopped.")

# Kill second PiFrame instance
app_proc.kill()
print("Terminated second PiFrame instance.")

if os.path.exists(out_mp4):
    size = os.path.getsize(out_mp4)
    print(f"SUCCESS! Output MP4 recorded: {out_mp4} ({size / 1024:.1f} KB)")
else:
    print("Output MP4 was not created!")
    stdout, stderr = capture_proc.communicate()
    print("STDOUT:", stdout)
    print("STDERR:", stderr)
