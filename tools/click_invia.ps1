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

# Move cursor to 'Invia' button (518, 657)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(518, 657)
Start-Sleep -Milliseconds 200

# Click left button
[WinMouse]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero) # Down
Start-Sleep -Milliseconds 100
[WinMouse]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero) # Up
Start-Sleep -Milliseconds 100
