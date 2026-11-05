$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-Process | Where-Object { $_.SessionId -eq 1 } | Select-Object -First 15 Id, ProcessName, MainWindowTitle
}
