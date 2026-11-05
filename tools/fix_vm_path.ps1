$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    # Check current PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $sysPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    Write-Host "Current User Path: $userPath"
    
    $piDir = "C:\Users\User\.pi\agent\bin"
    $npmDir = "C:\Users\User\AppData\Roaming\npm"
    
    # Ensure Pi is in User PATH
    if ($userPath -notmatch [regex]::Escape($piDir)) {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$piDir;$npmDir", "User")
        Write-Host "Added $piDir to User PATH."
    }
    
    # Check pi command
    $piCmd = Get-Command pi -ErrorAction SilentlyContinue
    if ($piCmd) {
        Write-Host "Pi found at: $($piCmd.Source)"
    } else {
        Write-Host "Checking direct path $piDir\pi.cmd..."
        Test-Path "$piDir\pi.cmd"
    }
}
