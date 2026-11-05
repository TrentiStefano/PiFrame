$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-Content "C:\Users\User\.piframe\runtime\daemon.pid" -ErrorAction SilentlyContinue
    Get-Content "C:\Users\User\.piframe\runtime\daemon.json" -ErrorAction SilentlyContinue
}
