$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $scriptContent = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bmp.Save("C:\Users\User\desktop_capture.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bmp.Dispose()
'@
    Set-Content -Path "C:\Users\User\capture.ps1" -Value $scriptContent
    schtasks /create /tn "Snap" /tr "powershell.exe -ExecutionPolicy Bypass -File C:\Users\User\capture.ps1" /sc ONCE /st 23:59 /it /f
    schtasks /run /tn "Snap"
    Start-Sleep -Seconds 2
}

$bytes = Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    [System.IO.File]::ReadAllBytes("C:\Users\User\desktop_capture.png")
}
[System.IO.File]::WriteAllBytes("scratch/vm_desktop_now.png", $bytes)
Write-Host "Captured scratch/vm_desktop_now.png! Size: $($bytes.Length) bytes"
