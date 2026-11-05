$proc = Start-Process -FilePath "C:\Personale\Repos\PiFrame\PiFrame\apps\pi_frame\build\windows\x64\runner\Release\PiFrame.exe" -PassThru
Start-Sleep -Seconds 3
$p = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if ($p) {
    Write-Host "Launched PiFrame Instance! PID: $($p.Id), Title: '$($p.MainWindowTitle)', HWND: $($p.MainWindowHandle)"
    # Clean up test process
    Stop-Process -Id $p.Id -Force
} else {
    Write-Host "Process exited immediately"
}
