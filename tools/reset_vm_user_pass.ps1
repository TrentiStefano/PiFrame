$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    # Check User account
    net user User
    # Set password to "password" explicitly
    net user User password
    
    # Configure auto logon properly
    $reg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $reg -Name "AutoAdminLogon" -Value "1"
    Set-ItemProperty -Path $reg -Name "DefaultUserName" -Value "User"
    Set-ItemProperty -Path $reg -Name "DefaultPassword" -Value "password"
    Set-ItemProperty -Path $reg -Name "DefaultDomainName" -Value $env:COMPUTERNAME
    
    # Also disable lock screen if possible
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen" -Value 1 -ErrorAction SilentlyContinue
}
