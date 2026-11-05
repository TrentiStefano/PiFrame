$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $proc = Start-Process -FilePath "C:\Users\User\AppData\Local\Programs\PiFrame\PiFrame.exe" -PassThru
    Start-Sleep -Seconds 3
    Get-Process -Id $proc.Id -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, MainWindowTitle, HasExited, ExitCode
}
