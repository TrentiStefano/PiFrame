$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $p = Start-Process -FilePath "C:\Users\User\AppData\Local\Programs\PiFrame\PiFrame.exe" -PassThru
    Start-Sleep -Seconds 4
    if ($p.HasExited) {
        Write-Host "Exited with code: $($p.ExitCode)"
    } else {
        Write-Host "Still running! PID: $($p.Id), HWND: $($p.MainWindowHandle), Title: '$($p.MainWindowTitle)'"
    }
}
