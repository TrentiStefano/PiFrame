$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$mouse = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_SyntheticMouse

Write-Host "Moving mouse to recent session card (45750, 33700)..."
Invoke-CimMethod -InputObject $mouse -MethodName SetAbsolutePosition -Arguments @{
    horizontalPosition = 45750
    verticalPosition = 33700
} | Out-Null
Start-Sleep -Milliseconds 200

Write-Host "Clicking recent session..."
Invoke-CimMethod -InputObject $mouse -MethodName ClickButton -Arguments @{ buttonIndex = 1 } | Out-Null
Start-Sleep -Seconds 3

& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == 1572868 else data
im = Image.frombytes('RGB', (1024, 768), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_session_opened.png')
print('Saved scratch/hyperv_session_opened.png!')
"
