$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-Process | Where-Object { $_.ProcessName -match "git" } | Select-Object Id, ProcessName
} -ErrorAction SilentlyContinue
