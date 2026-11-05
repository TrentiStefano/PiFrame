$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$keyboard = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard
if ($keyboard) {
    Write-Host "Found Msvm_Keyboard! Sending TypeCtrlAltDel..."
    Invoke-CimMethod -InputObject $keyboard -MethodName TypeCtrlAltDel
    Write-Host "Sent Ctrl+Alt+Del successfully!"
} else {
    Write-Host "Msvm_Keyboard not found."
}
