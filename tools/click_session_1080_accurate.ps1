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

$log = "C:\Users\User\click.log"
$p = Get-Process -Name PiFrame -ErrorAction SilentlyContinue | Select-Object -First 1

$msg = "Script started at $(Get-Date). "
if ($p) {
    $msg += "PiFrame PID: $($p.Id), HWND: $($p.MainWindowHandle). "
    [WinUtil]::SetForegroundWindow($p.MainWindowHandle)
    Start-Sleep -Milliseconds 250
} else {
    $msg += "PiFrame process NOT found! "
}

# Move cursor
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(1330, 512)
Start-Sleep -Milliseconds 200

# Click
[WinUtil]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero) # Down
Start-Sleep -Milliseconds 100
[WinUtil]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero) # Up

$msg += "Clicked at Point(1330, 512). Position now: $([System.Windows.Forms.Cursor]::Position)"
Set-Content -Path $log -Value $msg
