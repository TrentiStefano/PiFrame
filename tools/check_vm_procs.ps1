$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-Process | Where-Object { $_.ProcessName -match "PiFrame|node" } | Select-Object Id, ProcessName, MainWindowTitle, MainWindowHandle, SessionId
}
