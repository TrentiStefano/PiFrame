$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $bmp.Save("C:\Users\User\current_screen.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bmp.Dispose()
    (Get-Item "C:\Users\User\current_screen.png").Length
}

$bytes = Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    [System.IO.File]::ReadAllBytes("C:\Users\User\current_screen.png")
}
[System.IO.File]::WriteAllBytes("scratch/vm_current_screen.png", $bytes)
Write-Host "Captured scratch/vm_current_screen.png, size: $($bytes.Length)"
