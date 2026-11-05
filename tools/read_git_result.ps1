$msg = Get-Content "C:\Users\User\mock_git_created.txt" -ErrorAction SilentlyContinue
Set-Content "C:\Users\User\git_result_display.txt" "RESULT: $msg"
