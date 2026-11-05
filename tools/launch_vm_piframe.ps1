$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $action = New-ScheduledTaskAction -Execute "C:\Users\User\AppData\Local\Programs\PiFrame\PiFrame.exe" -WorkingDirectory "C:\Users\User\AppData\Local\Programs\PiFrame"
    Register-ScheduledTask -TaskName "LaunchPiFrame" -Action $action -User "User" -Password "password" -Force
    Start-ScheduledTask -TaskName "LaunchPiFrame"
    Start-Sleep -Seconds 3
    Get-Process | Where-Object { $_.ProcessName -match "PiFrame|node|pi" } | Select-Object Id, ProcessName, MainWindowTitle, SessionId
}
