Add-Type -AssemblyName System.Windows.Forms
$out = "C:\Users\User\git_search.txt"

$candidates = @(
    "C:\Program Files\Git\cmd\git.exe",
    "C:\Program Files\Git\bin\git.exe",
    "C:\Program Files (x86)\Git\cmd\git.exe",
    "C:\Users\User\AppData\Local\Programs\Git\cmd\git.exe",
    "C:\Users\User\AppData\Local\GitHubDesktop\app-*\resources\app\git\cmd\git.exe"
)

$found = $null
foreach ($c in $candidates) {
    $matched = Get-Item $c -ErrorAction SilentlyContinue
    if ($matched) {
        $found = $matched.FullName
        break
    }
}

if ($found) {
    Set-Content -Path $out -Value "FOUND: $found"
} else {
    Set-Content -Path $out -Value "NOT_FOUND"
}
