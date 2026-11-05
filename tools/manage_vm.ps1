$ErrorActionPreference = "Stop"
Write-Host "Restoring snapshot 'PiFrame' on VM 'Win11'..."
Restore-VMSnapshot -VMName "Win11" -Name "PiFrame" -Confirm:$false
Write-Host "Starting VM 'Win11'..."
Start-VM -Name "Win11"
Start-Sleep -Seconds 2
$vm = Get-VM -Name "Win11"
Write-Host "VM State: $($vm.State), Status: $($vm.Status)"
