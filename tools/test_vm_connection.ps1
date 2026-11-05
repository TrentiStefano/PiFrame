$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Write-Host "Connecting to VM 'Win11' via PowerShell Direct..."
try {
    $res = Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            PiPath = (Get-Command pi -ErrorAction SilentlyContinue).Source
            PiFrame = (Get-Command PiFrame -ErrorAction SilentlyContinue).Source
        }
    } -ErrorAction Stop
    $res | Format-List
} catch {
    Write-Host "Error connecting to VM: $_"
}
