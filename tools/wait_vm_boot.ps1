$done = $false
for ($i = 0; $i -lt 12; $i++) {
    Start-Sleep -Seconds 4
    & tools/test_hyperv_screen.ps1 | Out-Null
    $data = [System.IO.File]::ReadAllBytes("scratch/hyperv_screen.raw")
    if ($data.Length -gt 100) {
        # Check if there are non-black, non-pure-white pixels
        $sum = 0
        for ($j = 4; $j -lt [Math]::Min($data.Length, 4000); $j += 4) {
            $sum += $data[$j]
        }
        Write-Host "Sample pixel sum: $sum"
    }
}
& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == (1920*1080*2 + 4) else data
im = Image.frombytes('RGB', (1920, 1080), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_1080p_boot.png')
print('Saved scratch/hyperv_1080p_boot.png!')
"
