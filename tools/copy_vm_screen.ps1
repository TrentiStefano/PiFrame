$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

$bytes = Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    [System.IO.File]::ReadAllBytes("C:\Users\User\screen_test.png")
}
[System.IO.File]::WriteAllBytes("scratch/vm_screen_test.png", $bytes)
Write-Host "Copied scratch/vm_screen_test.png! Size: $($bytes.Length) bytes"
