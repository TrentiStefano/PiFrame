$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Write-Host "Searching for PiFrame and Recordly inside VM..."
    Get-ChildItem -Path "C:\Users\User\AppData\Local", "C:\Users\User\Desktop", "C:\Program Files", "C:\Program Files (x86)" -Filter "*PiFrame*" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object FullName
    Get-ChildItem -Path "C:\Users\User\AppData\Local", "C:\Users\User\Desktop", "C:\Program Files", "C:\Program Files (x86)" -Filter "*Recordly*" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object FullName
}
