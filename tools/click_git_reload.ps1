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

# Click [ Git Changes ] tab (X: 720, Y: 105)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(720, 105)
Start-Sleep -Milliseconds 200
[WinMouse]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 80
[WinMouse]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 300

# Click reload button (X: 938, Y: 105)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(938, 105)
Start-Sleep -Milliseconds 200
[WinMouse]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 80
[WinMouse]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
