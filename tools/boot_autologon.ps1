$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $regPath -Name "AutoAdminLogon" -Value "1"
    Set-ItemProperty -Path $regPath -Name "DefaultUserName" -Value "User"
    Set-ItemProperty -Path $regPath -Name "DefaultPassword" -Value "password"
}
Restart-VM -VMName "Win11" -Force
Start-Sleep -Seconds 14

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    quser
}
