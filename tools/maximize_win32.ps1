$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "Sending Alt + Tab..."
Invoke-CimMethod -InputObject $keyboard -MethodName PressKey -Arguments @{ keyCode = 18 } | Out-Null # Alt
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 9 } | Out-Null # Tab
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName ReleaseKey -Arguments @{ keyCode = 18 } | Out-Null
Start-Sleep -Milliseconds 600

Write-Host "Sending Alt + Space..."
Invoke-CimMethod -InputObject $keyboard -MethodName PressKey -Arguments @{ keyCode = 18 } | Out-Null # Alt
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 32 } | Out-Null # Space
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName ReleaseKey -Arguments @{ keyCode = 18 } | Out-Null
Start-Sleep -Milliseconds 400

Write-Host "Sending 'x' for Maximize..."
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 88 } | Out-Null # 'x'
Start-Sleep -Seconds 2

& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == 1572868 else data
im = Image.frombytes('RGB', (1024, 768), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_alt_space_x.png')
print('Saved scratch/hyperv_alt_space_x.png!')
"
