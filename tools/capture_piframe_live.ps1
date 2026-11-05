$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $scriptContent = @'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bmp.Save("C:\Users\User\piframe_live.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bmp.Dispose()
'@
    Set-Content -Path "C:\Users\User\snap.ps1" -Value $scriptContent
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Users\User\snap.ps1"
    $principal = New-ScheduledTaskPrincipal -UserId "User" -LogonType Interactive
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName "TakeSnap" -Action $action -Principal $principal -Settings $settings -Force
    Start-ScheduledTask -TaskName "TakeSnap"
    Start-Sleep -Seconds 3
    (Get-Item "C:\Users\User\piframe_live.png").Length
}

$bytes = Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    [System.IO.File]::ReadAllBytes("C:\Users\User\piframe_live.png")
}
[System.IO.File]::WriteAllBytes("scratch/piframe_live_vm.png", $bytes)
Write-Host "Captured scratch/piframe_live_vm.png, size: $($bytes.Length) bytes!"
