$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $action = New-ScheduledTaskAction -Execute "C:\Users\User\AppData\Local\Programs\PiFrame\PiFrame.exe" -WorkingDirectory "C:\Users\User\AppData\Local\Programs\PiFrame"
    $principal = New-ScheduledTaskPrincipal -UserId "User" -LogonType Interactive
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName "StartPiFrameInteractive" -Action $action -Principal $principal -Settings $settings -Force
    Start-ScheduledTask -TaskName "StartPiFrameInteractive"
    Start-Sleep -Seconds 5
    Get-Process | Where-Object { $_.ProcessName -match "PiFrame|node" } | Select-Object Id, ProcessName, MainWindowTitle, MainWindowHandle, SessionId
}
