$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "Sending Enter..."
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 } | Out-Null
Start-Sleep -Seconds 1

Write-Host "Sending password..."
Invoke-CimMethod -InputObject $keyboard -MethodName TypeText -Arguments @{ asciiText = "password" }
Start-Sleep -Seconds 1

Write-Host "Sending Enter..."
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 13 }
Start-Sleep -Seconds 4
