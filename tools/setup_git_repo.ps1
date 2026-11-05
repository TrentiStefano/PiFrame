$repo = "C:\Users\User\Repos\test"
if (!(Test-Path $repo)) {
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
}

$lib = Join-Path $repo "lib"
New-Item -ItemType Directory -Path $lib -Force | Out-Null

$appShell = @"
import 'package:flutter/material.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final bg = Color(0xFF232634);
    return Scaffold(
      backgroundColor: bg,
      body: Center(child: Text('PiFrame Workspace')),
    );
  }
}
"@
Set-Content -Path (Join-Path $lib "app_shell.dart") -Value $appShell

# Find git
$gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
if (!$gitExe) {
    $candidates = @(
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Program Files\Git\bin\git.exe",
        "C:\Program Files (x86)\Git\cmd\git.exe",
        "C:\Users\User\AppData\Local\Programs\Git\cmd\git.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $gitExe = $c; break }
    }
}

if ($gitExe) {
    & $gitExe -C $repo init
    & $gitExe -C $repo config user.name "Stefano Trenti"
    & $gitExe -C $repo config user.email "stefanotrenti.st@gmail.com"
    & $gitExe -C $repo add .
    & $gitExe -C $repo commit -m "feat: initial commit with app shell"

    # Modify file to create realistic diff
    $appShellModified = @"
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

    return Scaffold(
      backgroundColor: bg,
      body: BentoTriptychWorkspace(
        chat: TranscriptView(),
        diffReview: ReviewFileDiffViewer(),
      ),
    );
  }
}
"@
    Set-Content -Path (Join-Path $lib "app_shell.dart") -Value $appShellModified
    Write-Host "Git repo ready at $repo with modified diff!"
} else {
    Write-Host "Git not found, sample files created."
}
