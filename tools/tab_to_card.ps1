$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "Tabbing 3 times to Quick Launch Card..."
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 9 } | Out-Null # Tab 1
Start-Sleep -Milliseconds 150
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 9 } | Out-Null # Tab 2
Start-Sleep -Milliseconds 150
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 9 } | Out-Null # Tab 3
Start-Sleep -Milliseconds 250

Write-Host "Pressing Space to activate Quick Launch Card..."
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 32 } | Out-Null # Space
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 } | Out-Null # Enter
Start-Sleep -Seconds 4

& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == 1572868 else data
im = Image.frombytes('RGB', (1024, 768), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_after_card_tab.png')
print('Saved scratch/hyperv_after_card_tab.png!')
"
