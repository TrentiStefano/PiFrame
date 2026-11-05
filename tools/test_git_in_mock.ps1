$git = "C:\Users\User\AppData\Local\Programs\PiFrame\cmd\git.exe"
$repo = "C:\Users\User\Projects\piframe-mock"
$out = & $git -C $repo status --porcelain
Set-Content "C:\Users\User\mock_git_status.txt" $out
