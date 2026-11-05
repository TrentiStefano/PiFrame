$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $sysPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $piDir = "C:\Users\User\.pi\agent\bin"
    $nodeDir = "C:\Users\User\AppData\Local\pi-node\current"
    
    if ($sysPath -notmatch [regex]::Escape($piDir)) {
        [Environment]::SetEnvironmentVariable("Path", "$sysPath;$piDir;$nodeDir", "Machine")
        Write-Host "Added $piDir to System PATH."
    }
}
