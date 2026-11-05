$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "Sending Ctrl + K to open Command Palette..."
Invoke-CimMethod -InputObject $keyboard -MethodName PressKey -Arguments @{ keyCode = 17 } | Out-Null # Ctrl
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 75 } | Out-Null # 'K'
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName ReleaseKey -Arguments @{ keyCode = 17 } | Out-Null # Release Ctrl
Start-Sleep -Seconds 2

& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == 1572868 else data
im = Image.frombytes('RGB', (1024, 768), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_cmd_palette.png')
print('Saved scratch/hyperv_cmd_palette.png!')
"
