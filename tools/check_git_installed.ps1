$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Test-Path "C:\Program Files\Git\cmd\git.exe"
    Test-Path "C:\Program Files\Git\bin\git.exe"
} -ErrorAction SilentlyContinue
