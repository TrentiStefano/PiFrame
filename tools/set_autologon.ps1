$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $regPath -Name "AutoAdminLogon" -Value "1"
    Set-ItemProperty -Path $regPath -Name "DefaultUserName" -Value "User"
    Set-ItemProperty -Path $regPath -Name "DefaultPassword" -Value "password"
    Write-Host "AutoAdminLogon configured for 'User'."
    Get-ItemProperty -Path $regPath -Name AutoAdminLogon, DefaultUserName
}
