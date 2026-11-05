$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-Item "C:\Users\User\screen_test.png" -ErrorAction SilentlyContinue | Select-Object Name, Length, LastWriteTime
}
