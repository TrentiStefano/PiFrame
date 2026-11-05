$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-Item "C:\Users\User\desktop_capture.png" -ErrorAction SilentlyContinue | Select-Object Name, Length, LastWriteTime
    Get-ScheduledTaskInfo -TaskName "Snap" | Select-Object LastRunTime, LastTaskResult
}
