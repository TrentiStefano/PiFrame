$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$mouse = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_Keyboard
$synMouse = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_SyntheticMouse

$btnState = Invoke-CimMethod -InputObject $synMouse -MethodName GetButtonState -Arguments @{ buttonIndex = 1 }
Write-Host "Button 1 IsDown: $($btnState.IsDown)"
if ($btnState.IsDown) {
    Invoke-CimMethod -InputObject $synMouse -MethodName SetButtonState -Arguments @{ buttonIndex = 1; isDown = $false }
    Write-Host "Released button 1."
}
