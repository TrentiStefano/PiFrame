Write-Host "Stopping VM Win11..."
Stop-VM -VMName "Win11" -TurnOff
Write-Host "Restoring snapshot 'PiFrame'..."
Restore-VMSnapshot -VMName "Win11" -Name "PiFrame" -Confirm:$false
Write-Host "Starting VM Win11..."
Start-VM -Name "Win11"
Start-Sleep -Seconds 3
Get-VM -Name "Win11" | Select-Object Name, State, Status
