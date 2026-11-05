$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $action = New-ScheduledTaskAction -Execute "C:\Users\User\AppData\Local\Programs\PiFrame\PiFrame.exe" -WorkingDirectory "C:\Users\User\AppData\Local\Programs\PiFrame"
    $principal = New-ScheduledTaskPrincipal -UserId "User" -LogonType Interactive
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName "RunPiFrame" -Action $action -Principal $principal -Settings $settings -Force
    Start-ScheduledTask -TaskName "RunPiFrame"
    Start-Sleep -Seconds 4
    Get-Process -Name PiFrame -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, MainWindowTitle, MainWindowHandle, SessionId
}
