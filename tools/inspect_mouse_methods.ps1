$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$mouse = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_SyntheticMouse
(Get-CimClass -Namespace root\virtualization\v2 -ClassName Msvm_SyntheticMouse).CimClassMethods | Select-Object Name, Parameters
