$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$mouse = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_SyntheticMouse

Write-Host "Moving mouse to PiFrame icon at (2432, 25187)..."
Invoke-CimMethod -InputObject $mouse -MethodName SetAbsolutePosition -Arguments @{
    horizontalPosition = 2432
    verticalPosition = 25187
} | Out-Null
Start-Sleep -Milliseconds 200

Write-Host "Double clicking..."
Invoke-CimMethod -InputObject $mouse -MethodName ClickButton -Arguments @{ buttonIndex = 1 } | Out-Null
Start-Sleep -Milliseconds 80
Invoke-CimMethod -InputObject $mouse -MethodName ClickButton -Arguments @{ buttonIndex = 1 } | Out-Null
Start-Sleep -Seconds 4

& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == 1572868 else data
im = Image.frombytes('RGB', (1024, 768), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_after_doubleclick.png')
print('Saved scratch/hyperv_after_doubleclick.png!')
"
