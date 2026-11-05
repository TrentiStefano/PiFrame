$log = "C:\Users\User\git_status_check.txt"
$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (!$git) {
    if (Test-Path "C:\Program Files\Git\cmd\git.exe") {
        $git = "C:\Program Files\Git\cmd\git.exe"
    }
}

if ($git) {
    Set-Content -Path $log -Value "GIT_OK: $git"
} else {
    Set-Content -Path $log -Value "NO_GIT"
}
