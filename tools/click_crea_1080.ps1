Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinUtil {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@

$p = Get-Process -Name PiFrame -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p -and $p.MainWindowHandle -ne 0) {
    [WinUtil]::SetForegroundWindow($p.MainWindowHandle)
    Start-Sleep -Milliseconds 200
}

# Target exact center of Crea button (1082, 578)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(1082, 578)
Start-Sleep -Milliseconds 200

[WinUtil]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero) # Down
Start-Sleep -Milliseconds 100
[WinUtil]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero) # Up
Start-Sleep -Seconds 4
