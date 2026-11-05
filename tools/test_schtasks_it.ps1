$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    # Kill previous test process
    Stop-Process -Name PiFrame -Force -ErrorAction SilentlyContinue

    schtasks /create /tn "RunGuiInSession1" /tr "C:\Users\User\AppData\Local\Programs\PiFrame\PiFrame.exe" /sc ONCE /st 23:59 /it /f
    schtasks /run /tn "RunGuiInSession1"
    Start-Sleep -Seconds 3
    Get-Process -Name PiFrame -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, MainWindowTitle, MainWindowHandle, SessionId
}
