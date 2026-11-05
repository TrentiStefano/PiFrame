Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinMouse {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@

$p = Get-Process -Name PiFrame -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p -and $p.MainWindowHandle -ne 0) {
    [WinMouse]::SetForegroundWindow($p.MainWindowHandle)
    Start-Sleep -Milliseconds 150
}

# 1. Click Moon icon at (1740, 25) to switch to Dark Mode
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(1740, 25)
Start-Sleep -Milliseconds 150
[WinMouse]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 60
[WinMouse]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 600

# 2. Click Quick Launch session card at (1300, 510)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(1300, 510)
Start-Sleep -Milliseconds 200
[WinMouse]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 80
[WinMouse]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Seconds 2
