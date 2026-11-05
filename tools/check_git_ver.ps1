$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "Running git --version via Win + R..."
Invoke-CimMethod -InputObject $keyboard -MethodName PressKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 82 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName ReleaseKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Milliseconds 800

$cmd = "cmd.exe /c `"git --version > C:\Users\User\git_ver.txt 2>&1`""
Invoke-CimMethod -InputObject $keyboard -MethodName TypeText -Arguments @{ asciiText = $cmd } | Out-Null
Start-Sleep -Milliseconds 300
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 } | Out-Null
Start-Sleep -Seconds 3
