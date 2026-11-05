$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "Typing password via TypeText directly into focused box..."
# Select all and delete anything first just in case
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 8 } | Out-Null # Backspace
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 8 } | Out-Null
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 8 } | Out-Null
Start-Sleep -Milliseconds 200

# Type 'password'
Invoke-CimMethod -InputObject $keyboard -MethodName TypeText -Arguments @{ asciiText = "password" } | Out-Null
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
im.save('scratch/hyperv_after_type_password.png')
print('Saved scratch/hyperv_after_type_password.png!')
"
