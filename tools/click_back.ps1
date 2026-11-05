Add-Type -AssemblyName System.Windows.Forms
# Set cursor to Back Arrow in Settings (X: 44, Y: 112)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(44, 112)
Start-Sleep -Milliseconds 100

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class M {
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@
# MOUSEEVENTF_LEFTDOWN = 0x02, MOUSEEVENTF_LEFTUP = 0x04
[M]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 60
[M]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
