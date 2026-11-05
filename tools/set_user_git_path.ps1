$gitCmd = "C:\Users\User\AppData\Local\Programs\Git\cmd"
$gitBin = "C:\Users\User\AppData\Local\Programs\Git\bin"
$p = [Environment]::GetEnvironmentVariable("Path", "User")
if ($p -notmatch [regex]::Escape($gitCmd)) {
    [Environment]::SetEnvironmentVariable("Path", "$p;$gitCmd;$gitBin", "User")
}
Set-Content "C:\Users\User\git_ready.txt" "GIT_CONFIGURED"
