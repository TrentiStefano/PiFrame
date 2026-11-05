$src = (Resolve-Path "scratch\mingit_unzipped").Path
$dest = "C:\Users\User\AppData\Local\Programs\Git"

$allFiles = Get-ChildItem -Path $src -Recurse -File
Write-Host "Copying $($allFiles.Count) MinGit files to VM $dest..."
$i = 0
foreach ($f in $allFiles) {
    $i++
    $rel = $f.FullName.Substring($src.Length).TrimStart("\")
    $target = Join-Path $dest $rel
    Copy-VMFile -VMName "Win11" -SourcePath $f.FullName -DestinationPath $target -CreateFullPath -FileSource Host -Force
    if ($i % 50 -eq 0) {
        Write-Host "Copied $i / $($allFiles.Count)..."
    }
}
Write-Host "MinGit copied to user profile!"
