$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "Triggering winget install Git.Git via Win + R..."
Invoke-CimMethod -InputObject $keyboard -MethodName PressKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 82 } | Out-Null
Start-Sleep -Milliseconds 100
Invoke-CimMethod -InputObject $keyboard -MethodName ReleaseKey -Arguments @{ keyCode = 91 } | Out-Null
Start-Sleep -Milliseconds 800

$cmd = "winget install --id Git.Git -e --silent --accept-source-agreements --accept-package-agreements"
Invoke-CimMethod -InputObject $keyboard -MethodName TypeText -Arguments @{ asciiText = $cmd } | Out-Null
Start-Sleep -Milliseconds 400
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 } | Out-Null
Start-Sleep -Seconds 12
