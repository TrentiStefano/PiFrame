$secPass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $secPass)

Invoke-Command -VMName "Win11" -Credential $cred -ScriptBlock {
    Get-Item "C:\Users\User\clip1_question_answering.mp4" -ErrorAction SilentlyContinue | Select-Object Name, Length
}
