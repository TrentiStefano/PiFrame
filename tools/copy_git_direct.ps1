$gitExe = (Resolve-Path "scratch\mingit_unzipped\cmd\git.exe").Path
Copy-VMFile -VMName "Win11" -SourcePath $gitExe -DestinationPath "C:\Users\User\AppData\Local\Programs\PiFrame\git.exe" -CreateFullPath -FileSource Host -Force
Copy-VMFile -VMName "Win11" -SourcePath $gitExe -DestinationPath "C:\Users\User\.pi\agent\bin\git.exe" -CreateFullPath -FileSource Host -Force
Write-Host "git.exe copied to PiFrame and Pi bin directories!"
