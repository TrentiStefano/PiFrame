$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Stop-Process -Name PiFrame -Force -ErrorAction SilentlyContinue
    Stop-Process -Name node -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-ScheduledTask -TaskName "StartPiFrameInteractive"
    Start-Sleep -Seconds 6
}

& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == 1572868 else data
im = Image.frombytes('RGB', (1024, 768), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_screen_restarted.png')
print('Saved scratch/hyperv_screen_restarted.png!')
"
