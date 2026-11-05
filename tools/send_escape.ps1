$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard

Write-Host "Sending Escape key to dismiss dialog..."
Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = 27 } | Out-Null
Start-Sleep -Seconds 1
