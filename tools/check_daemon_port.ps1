$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-NetTCPConnection -LocalPort 55713 -ErrorAction SilentlyContinue | Select-Object LocalAddress, LocalPort, State, OwningProcess
}
