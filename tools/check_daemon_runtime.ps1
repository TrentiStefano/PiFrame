$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-Process | Where-Object { $_.ProcessName -match "node" } | Select-Object Id, ProcessName, SessionId
    Get-Item "C:\Users\User\.piframe\runtime\*" -ErrorAction SilentlyContinue | Select-Object Name, Length
}
