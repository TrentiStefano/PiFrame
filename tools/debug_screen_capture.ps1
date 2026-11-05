$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    $cmd = 'powershell.exe -ExecutionPolicy Bypass -Command "& { Add-Type -AssemblyName System.Windows.Forms, System.Drawing; [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.ToString() | Out-File C:\Users\User\screen_info.log }" > C:\Users\User\task.log 2>&1'
    Set-Content -Path "C:\Users\User\run_test.bat" -Value $cmd
    schtasks /create /tn "TestBat" /tr "cmd.exe /c C:\Users\User\run_test.bat" /sc ONCE /st 23:59 /it /f
    schtasks /run /tn "TestBat"
    Start-Sleep -Seconds 3
    Get-Content "C:\Users\User\task.log" -ErrorAction SilentlyContinue
    Get-Content "C:\Users\User\screen_info.log" -ErrorAction SilentlyContinue
}
