$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-Content "C:\Users\User\task.log" -ErrorAction SilentlyContinue
    Get-Content "C:\Users\User\screen_info.log" -ErrorAction SilentlyContinue
}
