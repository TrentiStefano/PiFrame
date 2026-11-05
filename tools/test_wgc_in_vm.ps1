$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    # Find PiFrame window HWND
    $p = Get-Process -Name PiFrame -ErrorAction SilentlyContinue | Select-Object -First 1
    if (!$p) {
        Write-Host "PiFrame is not running!"
        return
    }

    $hwnd = $p.MainWindowHandle
    Write-Host "PiFrame PID: $($p.Id), HWND: $hwnd"

    # Script to run in Session 1
    $script = @"
`$p = Start-Process -FilePath "C:\Users\User\wgc-capture.exe" -ArgumentList '{"displayId":0,"outputPath":"C:/Users/User/vm_recording.mp4","fps":30}' -PassThru -NoNewWindow
Start-Sleep -Seconds 3
Stop-Process -Id `$p.Id -Force
"@
    Set-Content -Path "C:\Users\User\record.ps1" -Value $script

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Users\User\record.ps1"
    $principal = New-ScheduledTaskPrincipal -UserId "User" -LogonType Interactive
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName "RecordScreen" -Action $action -Principal $principal -Settings $settings -Force
    Start-ScheduledTask -TaskName "RecordScreen"
    Start-Sleep -Seconds 5

    Get-Item "C:\Users\User\vm_recording.mp4" -ErrorAction SilentlyContinue | Select-Object Name, Length
}
