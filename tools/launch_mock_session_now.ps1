$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "1. Clicking '+ Nuova sessione'..."
Invoke-CimMethod -InputObject $keyboard -MethodName PressKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 82 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName ReleaseKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Milliseconds 800

$cmd = "wscript.exe C:\Users\User\run_silent.vbs"
Invoke-CimMethod -InputObject $keyboard -MethodName TypeText -Arguments @{ asciiText = $cmd } | Out-Null
Start-Sleep -Milliseconds 300
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 } | Out-Null
Start-Sleep -Seconds 3

Write-Host "2. Typing path C:\Users\User\Projects\piframe-mock..."
$targetPath = "C:\Users\User\Projects\piframe-mock"
Invoke-CimMethod -InputObject $keyboard -MethodName TypeText -Arguments @{ asciiText = $targetPath } | Out-Null
Start-Sleep -Seconds 1

Write-Host "3. Pressing Enter to create session..."
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 } | Out-Null
Start-Sleep -Seconds 6

& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == (1920*1080*2 + 4) else data
im = Image.frombytes('RGB', (1920, 1080), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_mock_created_with_git.png')
print('Saved scratch/hyperv_mock_created_with_git.png! Size:', im.size)
"
