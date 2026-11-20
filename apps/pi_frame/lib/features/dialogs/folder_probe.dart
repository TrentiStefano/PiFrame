import 'dart:io';

import 'package:flutter/foundation.dart';

/// What the new-session dialog knows about the typed folder.
enum FolderStatus {
  /// Nothing typed.
  empty,

  /// The path does not exist on this machine.
  notFound,

  /// An existing folder that is not a Git repository.
  folder,

  /// An existing Git repository. [FolderProbe.branch] is null on a detached HEAD.
  gitRepo,

  /// Web build: the daemon may run elsewhere, so the path cannot be checked.
  unverified,
}

class FolderProbe {
  const FolderProbe(this.status, {this.branch});

  final FolderStatus status;
  final String? branch;

  /// Whether a session can be created in this folder.
  bool get isValid => switch (status) {
    FolderStatus.folder || FolderStatus.gitRepo || FolderStatus.unverified => true,
    FolderStatus.empty || FolderStatus.notFound => false,
  };
}

/// Checks [path] against the local filesystem: existence, then whether it is a
/// Git repository and, if cheap to read, the branch named by `HEAD`.
///
/// The daemon has no command that checks a path, so this runs in the app. When the
/// app and the daemon run on different hosts, the result describes the app's filesystem.
FolderProbe probeFolder(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return const FolderProbe(FolderStatus.empty);
  if (kIsWeb) return const FolderProbe(FolderStatus.unverified);
  try {
    if (!Directory(trimmed).existsSync()) {
      return const FolderProbe(FolderStatus.notFound);
    }
    final marker = '$trimmed${Platform.pathSeparator}.git';
    if (!FileSystemEntity.isDirectorySync(marker) && !FileSystemEntity.isFileSync(marker)) {
      return const FolderProbe(FolderStatus.folder);
    }
    return FolderProbe(FolderStatus.gitRepo, branch: _readBranch(marker));
  } catch (_) {
    return const FolderProbe(FolderStatus.notFound);
  }
}

/// Reads the branch from `HEAD`. A `.git` file (worktrees, submodules) points to
/// the real git directory with `gitdir: <path>`.
String? _readBranch(String gitMarker) {
  try {
    var gitDir = gitMarker;
    if (FileSystemEntity.isFileSync(gitMarker)) {
      final pointer = File(gitMarker).readAsStringSync().trim();
      if (!pointer.startsWith('gitdir:')) return null;
      final target = pointer.substring('gitdir:'.length).trim();
      gitDir = File(target).isAbsolute ? target : '${File(gitMarker).parent.path}${Platform.pathSeparator}$target';
    }
    final headFile = File('$gitDir${Platform.pathSeparator}HEAD');
    if (!headFile.existsSync()) return null;
    final head = headFile.readAsStringSync().trim();
    const prefix = 'ref: refs/heads/';
    if (!head.startsWith(prefix)) return null;
    final branch = head.substring(prefix.length).trim();
    return branch.isEmpty ? null : branch;
  } catch (_) {
    return null;
  }
}
