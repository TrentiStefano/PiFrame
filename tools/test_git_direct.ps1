$git = "C:\Users\User\AppData\Local\Programs\Git\cmd\git.exe"
$repo = "C:\Users\User\Projects\piframe-mock"
$p = Start-Process -FilePath $git -ArgumentList "-C `"$repo`" status" -PassThru -NoNewWindow -RedirectStandardOutput "C:\Users\User\git_out.txt" -RedirectStandardError "C:\Users\User\git_err.txt"
$p.WaitForExit(4000)
Set-Content "C:\Users\User\git_exit.txt" "EXIT: $($p.ExitCode)"
