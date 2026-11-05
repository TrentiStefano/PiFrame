# 1. Add Git to System PATH permanently
$sysPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$gitCmd = "C:\Users\User\AppData\Local\Programs\Git\cmd"
$gitBin = "C:\Users\User\AppData\Local\Programs\Git\mingw64\bin"

if ($sysPath -notmatch [regex]::Escape($gitCmd)) {
    [Environment]::SetEnvironmentVariable("Path", "$sysPath;$gitCmd;$gitBin", "Machine")
}

# 2. Add modified lines to create real diff
$repo = "C:\Users\User\Projects\piframe-mock"
$git = "$gitCmd\git.exe"

# Make sure lib dir and files exist
$lib = Join-Path $repo "lib"
if (!(Test-Path $lib)) { New-Item -ItemType Directory -Path $lib -Force | Out-Null }

$shellPath = Join-Path $lib "app_shell.dart"
$shellContent = @"
import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    // Official PiFrame Dark Theme Normative Tokens
    final bg = FrameTokens.dark.background; // #161c27
    final chassis = FrameTokens.dark.chassis; // #121721
    final accent = FrameTokens.dark.accent; // #5f9fc5
    final thinking = FrameTokens.dark.thinking; // #81b2cf

    return Scaffold(
      backgroundColor: bg,
      body: BentoTriptychWorkspace(
        chat: TranscriptView(),
        diffReview: ReviewFileDiffViewer(),
        terminal: HardwareTerminal(),
      ),
    );
  }
}
"@
Set-Content -Path $shellPath -Value $shellContent

# Commit original then modify
& $git -C $repo config user.name "User"
& $git -C $repo config user.email "user@piframe.dev"
& $git -C $repo add .
& $git -C $repo commit -m "feat: base architecture"

# Modify to have active diff
Add-Content -Path $shellPath -Value "`n// New theme token additions`nfinal darkSurface = FrameTokens.dark.surface;"
Add-Content -Path (Join-Path $repo "README.md") -Value "`n## Live Git Diff Review Ready"

# 3. Kill node.exe so pi-agentd restarts with Git in PATH
Stop-Process -Name node -Force -ErrorAction SilentlyContinue

Set-Content "C:\Users\User\git_setup_done.txt" "GIT_SETUP_COMPLETED"
