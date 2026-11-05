$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    # Stop session 0 instance
    Stop-Process -Name PiFrame -Force -ErrorAction SilentlyContinue
    Stop-Process -Name node -Force -ErrorAction SilentlyContinue

    schtasks /run /tn "LaunchPiFrame"
    Start-Sleep -Seconds 3
    Get-Process | Where-Object { $_.ProcessName -match "PiFrame|node" } | Select-Object Id, ProcessName, MainWindowTitle, SessionId
}
