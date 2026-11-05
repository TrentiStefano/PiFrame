$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $regPath -Name "AutoAdminLogon" -Value "1"
    Set-ItemProperty -Path $regPath -Name "DefaultUserName" -Value "User"
    Set-ItemProperty -Path $regPath -Name "DefaultPassword" -Value "password"
    Set-ItemProperty -Path $regPath -Name "ForceAutoLogon" -Value "1"
    Write-Host "Set AutoAdminLogon to 1"
}

Write-Host "Restarting Win11 VM..."
Restart-VM -VMName "Win11" -Force
Start-Sleep -Seconds 18

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    quser
}
