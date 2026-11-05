$sourceDir = (Resolve-Path "scratch\mock_repo").Path
$destDir = "C:\Users\User\Projects\piframe-mock"

$files = Get-ChildItem -Path $sourceDir -Recurse -Force
foreach ($f in $files) {
    if (!$f.PSIsContainer) {
        $relPath = $f.FullName.Substring($sourceDir.Length).TrimStart("\")
        $targetPath = Join-Path $destDir $relPath
        Copy-VMFile -VMName "Win11" -SourcePath $f.FullName -DestinationPath $targetPath -CreateFullPath -FileSource Host -Force
    }
}
Write-Host "Mock Git repo copied to VM at $destDir!"
