$git = "C:\Users\User\AppData\Local\Programs\PiFrame\cmd\git.exe"
$repo = "C:\Users\User\Projects\piframe-mock"

if (Test-Path $git) {
    $out = & $git -C $repo rev-parse --show-toplevel 2>&1
    Set-Content "C:\Users\User\git_debug.txt" "OUTPUT: $out"
} else {
    Set-Content "C:\Users\User\git_debug.txt" "GIT NOT FOUND AT $git"
}
