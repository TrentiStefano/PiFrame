param([switch]$NoLaunch)
# Resets the isolated PiFrame demo profile (C:\demo) to a known state.
$ErrorActionPreference = 'Continue'

# 1. Stop demo app, daemon and workers (never touches the real profile).
Get-Process PiFrame -ErrorAction SilentlyContinue | Where-Object { $_.Path -like 'C:\demo\*' } | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { $_.CommandLine -match 'C:\\demo\\(app|home)' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 800
Remove-Item C:\demo\home\.piframe\runtime\daemon.* -Force -ErrorAction SilentlyContinue

# 2. Repo back to the seed commit.
Push-Location C:\demo\orbit-api
git worktree list --porcelain | Select-String '^worktree ' | Select-Object -Skip 1 |
  ForEach-Object { git worktree remove --force ($_.Line -replace '^worktree ', '') }
git worktree prune
git checkout -q -f main
git reset -q --hard seed
git clean -qfd
git branch --list 'pi-subagents/*' | ForEach-Object { git branch -D $_.Trim() | Out-Null }
git stash clear
Pop-Location
Remove-Item C:\demo\worktrees -Recurse -Force -ErrorAction SilentlyContinue

# 3. Restore only the seed sessions (backup in C:\demo\seed-sessions).
Remove-Item C:\demo\home\.pi\agent\sessions -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item C:\demo\seed-sessions -Destination C:\demo\home\.pi\agent\sessions -Recurse
Remove-Item C:\demo\home\.piframe\context, C:\demo\home\.piframe\journal, C:\demo\home\.piframe\layout.json, C:\demo\home\.piframe\theme_settings.json -Recurse -Force -ErrorAction SilentlyContinue

if (-not $NoLaunch) {
  Start-Process -FilePath cmd.exe -ArgumentList '/c', 'C:\demo\launch-piframe.cmd' -WindowStyle Hidden
}
"reset done"
