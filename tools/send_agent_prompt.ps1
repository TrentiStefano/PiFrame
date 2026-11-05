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
    Start-Sleep -Milliseconds 300
}

# Click Composer text field (X: 280, Y: 620)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(280, 620)
Start-Sleep -Milliseconds 150
[WinUtil]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 60
[WinUtil]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 300

# Copy prompt to clipboard and paste (Ctrl+V)
$prompt = "Fai una domanda all utente usando lo strumento ask_user_question con due opzioni per scegliere l architettura"
[System.Windows.Forms.Clipboard]::SetText($prompt)
Start-Sleep -Milliseconds 200

# Send Ctrl+V
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 400

# Click Send button (X: 530, Y: 675)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(530, 675)
Start-Sleep -Milliseconds 150
[WinUtil]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 60
[WinUtil]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero)
