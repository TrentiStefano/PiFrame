$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "Pressing Win + R..."
# Press Windows key (VK_LWIN = 0x5B = 91)
Invoke-CimMethod -InputObject $keyboard -MethodName PressKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Milliseconds 100
# Press R (VK_R = 0x52 = 82)
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 82 } | Out-Null
Start-Sleep -Milliseconds 100
# Release Windows key
Invoke-CimMethod -InputObject $keyboard -MethodName ReleaseKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Seconds 1

Write-Host "Typing path to PiFrame..."
$path = "C:\Users\User\AppData\Local\Programs\PiFrame\PiFrame.exe"
Invoke-CimMethod -InputObject $keyboard -MethodName TypeText -Arguments @{ asciiText = $path } | Out-Null
Start-Sleep -Milliseconds 500

Write-Host "Pressing Enter..."
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 } | Out-Null
Start-Sleep -Seconds 5

& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == 1572868 else data
im = Image.frombytes('RGB', (1024, 768), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_after_win_r.png')
print('Saved scratch/hyperv_after_win_r.png!')
"
