$zip = "C:\Users\User\MinGit.zip"
$dest = "C:\Program Files\Git"

if (Test-Path $zip) {
    if (!(Test-Path $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    
    # Add to Machine and User PATH
    $cmdPath = "$dest\cmd"
    $binPath = "$dest\bin"
    
    $sysPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($sysPath -notmatch [regex]::Escape($cmdPath)) {
        [Environment]::SetEnvironmentVariable("Path", "$sysPath;$cmdPath;$binPath", "Machine")
    }
    
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notmatch [regex]::Escape($cmdPath)) {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$cmdPath;$binPath", "User")
    }
    
    Set-Content "C:\Users\User\git_extract_done.txt" "GIT_INSTALLED_OK"
}
