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
    Start-Sleep -Milliseconds 200
}

# Start wgc-capture.exe recording 60 FPS
$wgc = Start-Process -FilePath "C:\Users\User\wgc-capture.exe" -ArgumentList '{"displayId":0,"outputPath":"C:/Users/User/clip1_question_answering.mp4","fps":60}' -PassThru -NoNewWindow
Write-Host "Started recording to clip1_question_answering.mp4..."
Start-Sleep -Milliseconds 1200

# 1. Smoothly move cursor to Option 2: Native Fetch (X: 120, Y: 580)
$startX = [System.Windows.Forms.Cursor]::Position.X
$startY = [System.Windows.Forms.Cursor]::Position.Y
$targetX = 120
$targetY = 580

$steps = 25
for ($i = 1; $i -le $steps; $i++) {
    $curX = [int]($startX + ($targetX - $startX) * ($i / $steps))
    $curY = [int]($startY + ($targetY - $startY) * ($i / $steps))
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($curX, $curY)
    Start-Sleep -Milliseconds 16
}

Start-Sleep -Milliseconds 300

# Click Option 2
[WinMouse]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero) # Down
Start-Sleep -Milliseconds 80
[WinMouse]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero) # Up
Write-Host "Clicked Option 2 (Native Fetch)..."
Start-Sleep -Milliseconds 1000

# 2. Smoothly move cursor to 'Invia' button (X: 505, Y: 655)
$startX = [System.Windows.Forms.Cursor]::Position.X
$startY = [System.Windows.Forms.Cursor]::Position.Y
$targetX = 505
$targetY = 655

$steps = 25
for ($i = 1; $i -le $steps; $i++) {
    $curX = [int]($startX + ($targetX - $startX) * ($i / $steps))
    $curY = [int]($startY + ($targetY - $startY) * ($i / $steps))
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($curX, $curY)
    Start-Sleep -Milliseconds 16
}

Start-Sleep -Milliseconds 300

# Click 'Invia' button
[WinMouse]::mouse_event(0x02, 0, 0, 0, [UIntPtr]::Zero) # Down
Start-Sleep -Milliseconds 80
[WinMouse]::mouse_event(0x04, 0, 0, 0, [UIntPtr]::Zero) # Up
Write-Host "Clicked 'Invia'..."

# Wait 2.5s for answer submission & dialog dismissal
Start-Sleep -Milliseconds 2500

# Stop wgc-capture cleanly by stopping process
Stop-Process -Id $wgc.Id -Force
Write-Host "Recording finished and finalized!"
