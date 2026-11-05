$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Set-DisplayResolution -Width 1920 -Height 1080 -Force -ErrorAction SilentlyContinue
}
