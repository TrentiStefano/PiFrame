$hasGit = Test-Path "C:\Program Files\Git\cmd\git.exe"
Set-Content "C:\Users\User\git_progfiles.txt" "HAS_GIT: $hasGit"
