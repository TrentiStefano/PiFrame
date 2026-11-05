$git = "C:\Users\User\AppData\Local\Programs\Git\cmd\git.exe"
$repo = "C:\Users\User\Projects\piframe-mock"

if (Test-Path $git) {
    & $git -C $repo init
    & $git -C $repo config user.name "Stefano Trenti"
    & $git -C $repo config user.email "stefanotrenti.st@gmail.com"
    & $git -C $repo add .
    & $git -C $repo commit -m "feat: initial architecture"
    
    # Modify lib/app_shell.dart to have real unstaged diff
    $appShell = "C:\Users\User\Projects\piframe-mock\lib\app_shell.dart"
    Add-Content -Path $appShell -Value "`n// Additional theme tokens`nfinal darkAccent = FrameTokens.dark.accent;"
    
    $status = & $git -C $repo status --porcelain
    Set-Content "C:\Users\User\mock_git_created.txt" "STATUS: $status"
} else {
    Set-Content "C:\Users\User\mock_git_created.txt" "NO_GIT_EXE"
}
