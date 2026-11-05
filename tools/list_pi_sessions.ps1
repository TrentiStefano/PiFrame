$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Write-Host "Checking sessions folder inside VM..."
Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-ChildItem -Path "C:\Users\User\.pi\agent\sessions" -ErrorAction SilentlyContinue | Select-Object Name, Length, LastWriteTime
} -ErrorAction SilentlyContinue
