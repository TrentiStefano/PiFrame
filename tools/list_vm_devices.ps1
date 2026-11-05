$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
Get-CimAssociatedInstance -InputObject $vm | Select-Object -Property CimClass, ElementName
