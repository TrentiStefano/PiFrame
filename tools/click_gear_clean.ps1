$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$mouse = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_SyntheticMouse

Write-Host "Moving mouse to Settings gear button (54580, 2730)..."
Invoke-CimMethod -InputObject $mouse -MethodName SetAbsolutePosition -Arguments @{
    horizontalPosition = 54580
    verticalPosition = 2730
} | Out-Null
Start-Sleep -Milliseconds 250

Write-Host "Sending MouseDown then MouseUp..."
Invoke-CimMethod -InputObject $mouse -MethodName SetButtonState -Arguments @{ buttonIndex = 1; isDown = $true } | Out-Null
Start-Sleep -Milliseconds 120
Invoke-CimMethod -InputObject $mouse -MethodName SetButtonState -Arguments @{ buttonIndex = 1; isDown = $false } | Out-Null
Start-Sleep -Seconds 2

& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == 1572868 else data
im = Image.frombytes('RGB', (1024, 768), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_after_gear_click.png')
print('Saved scratch/hyperv_after_gear_click.png!')
"
