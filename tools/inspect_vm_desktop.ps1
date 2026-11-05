$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Write-Host "Desktop contents:"
    Get-ChildItem -Path "C:\Users\User\Desktop" | Select-Object Name
    Write-Host "User directories:"
    Get-ChildItem -Path "C:\Users\User" -Directory | Select-Object Name
}
