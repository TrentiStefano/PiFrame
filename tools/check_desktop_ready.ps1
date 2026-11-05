Start-Sleep -Seconds 4
& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == (1920*1080*2 + 4) else data
im = Image.frombytes('RGB', (1920, 1080), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_1080p_desktop_ready.png')
print('Saved scratch/hyperv_1080p_desktop_ready.png! Size:', im.size)
"
