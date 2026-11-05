$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "Tabbing 3 times to 'Crea' button..."
for ($i = 0; $i -lt 3; $i++) {
    Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 9 } | Out-Null # Tab
    Start-Sleep -Milliseconds 200
}

Write-Host "Pressing Space then Enter on 'Crea'..."
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 32 } | Out-Null # Space
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 } | Out-Null # Enter
Start-Sleep -Seconds 6

& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == (1920*1080*2 + 4) else data
im = Image.frombytes('RGB', (1920, 1080), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_mock_entered_now.png')
print('Saved scratch/hyperv_mock_entered_now.png! Size:', im.size)
"
