$src = (Resolve-Path "scratch\mingit_unzipped").Path
$dest = "C:\Users\User\AppData\Local\Programs\PiFrame"

# Copy git.exe directly to PiFrame root
Copy-VMFile -VMName "Win11" -SourcePath "$src\cmd\git.exe" -DestinationPath "$dest\git.exe" -CreateFullPath -FileSource Host -Force

# Copy entire cmd folder
$cmdFiles = Get-ChildItem -Path "$src\cmd"
foreach ($f in $cmdFiles) {
    Copy-VMFile -VMName "Win11" -SourcePath $f.FullName -DestinationPath "$dest\cmd\$($f.Name)" -CreateFullPath -FileSource Host -Force
}

# Copy mingw64 binaries
$mingwFiles = Get-ChildItem -Path "$src\mingw64\bin"
foreach ($f in $mingwFiles) {
    Copy-VMFile -VMName "Win11" -SourcePath $f.FullName -DestinationPath "$dest\mingw64\bin\$($f.Name)" -CreateFullPath -FileSource Host -Force
}

Write-Host "MinGit binaries deployed into PiFrame application directory!"
