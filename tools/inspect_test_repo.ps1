$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-ChildItem -Path "C:\Users\User\Repos\test" -Force | Select-Object Name
    git -C "C:\Users\User\Repos\test" status
}
