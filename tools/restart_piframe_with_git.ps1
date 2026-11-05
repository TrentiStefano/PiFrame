$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "1. Closing PiFrame with Alt + F4..."
Invoke-CimMethod -InputObject $keyboard -MethodName PressKey -Arguments @{ keyCode = 18 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 115 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName ReleaseKey -Arguments @{ keyCode = 18 } | Out-Null
Start-Sleep -Seconds 2

Write-Host "2. Killing any lingering node.exe via Win + R..."
Invoke-CimMethod -InputObject $keyboard -MethodName PressKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 82 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName ReleaseKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Milliseconds 800

$cmd = "cmd.exe /c `"taskkill /f /im node.exe & taskkill /f /im PiFrame.exe`""
Invoke-CimMethod -InputObject $keyboard -MethodName TypeText -Arguments @{ asciiText = $cmd } | Out-Null
Start-Sleep -Milliseconds 300
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 } | Out-Null
Start-Sleep -Seconds 2

Write-Host "3. Re-launching PiFrame cleanly..."
Invoke-CimMethod -InputObject $keyboard -MethodName PressKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 82 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName ReleaseKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Milliseconds 800

$cmd2 = "C:\Users\User\AppData\Local\Programs\PiFrame\PiFrame.exe"
Invoke-CimMethod -InputObject $keyboard -MethodName TypeText -Arguments @{ asciiText = $cmd2 } | Out-Null
Start-Sleep -Milliseconds 300
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 } | Out-Null
Start-Sleep -Seconds 7

& tools/test_hyperv_screen.ps1
python -c "
from PIL import Image
data = open('scratch/hyperv_screen.raw', 'rb').read()
raw_pixels = data[4:] if len(data) == (1920*1080*2 + 4) else data
im = Image.frombytes('RGB', (1920, 1080), raw_pixels, 'raw', 'BGR;16')
im.save('scratch/hyperv_restarted_with_git.png')
print('Saved scratch/hyperv_restarted_with_git.png! Size:', im.size)
"
