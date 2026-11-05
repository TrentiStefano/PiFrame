$git = "C:\Users\User\AppData\Local\Programs\Git\cmd\git.exe"
$repo = "C:\Users\User\Projects\piframe-mock"

& $git -C $repo status 2>&1 | Out-File -FilePath "C:\Users\User\git_err_log.txt" -Encoding utf8
