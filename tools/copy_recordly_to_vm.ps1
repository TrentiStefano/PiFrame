$files = Get-ChildItem -Path "C:\Program Files\Recordly\resources\app.asar.unpacked\electron\native\bin\win32-x64\*"
foreach ($f in $files) {
    Write-Host "Copying $($f.Name)..."
    Copy-VMFile -VMName "Win11" -SourcePath $f.FullName -DestinationPath ("C:\Users\User\" + $f.Name) -CreateFullPath -FileSource Host -Force
}
Write-Host "Copy complete."
