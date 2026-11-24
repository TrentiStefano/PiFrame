import 'package:flutter/foundation.dart';

import '../../data/platform/file_system_service.dart';

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
FolderProbe probeFolder(String path, FileSystemService files) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return const FolderProbe(FolderStatus.empty);
  if (kIsWeb) return const FolderProbe(FolderStatus.unverified);
  try {
    if (!files.directoryExistsSync(trimmed)) {
      return const FolderProbe(FolderStatus.notFound);
    }
    final marker = '$trimmed/.git';
    if (!files.directoryExistsSync(marker) && !files.fileExistsSync(marker)) {
      return const FolderProbe(FolderStatus.folder);
    }
    return FolderProbe(FolderStatus.gitRepo, branch: _readBranch(marker, files));
  } catch (_) {
    return const FolderProbe(FolderStatus.notFound);
  }
}

/// Reads the branch from `HEAD`. A `.git` file (worktrees, submodules) points to
/// the real git directory with `gitdir: <path>`.
String? _readBranch(String gitMarker, FileSystemService files) {
  try {
    var gitDir = gitMarker;
    if (files.fileExistsSync(gitMarker)) {
      final pointer = (files.readTextSync(gitMarker) ?? '').trim();
      if (!pointer.startsWith('gitdir:')) return null;
      final target = pointer.substring('gitdir:'.length).trim();
      final absolute = target.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(target);
      gitDir = absolute ? target : '${_parentOf(gitMarker)}/$target';
    }
    final headPath = '$gitDir/HEAD';
    if (!files.fileExistsSync(headPath)) return null;
    final head = (files.readTextSync(headPath) ?? '').trim();
    const prefix = 'ref: refs/heads/';
    if (!head.startsWith(prefix)) return null;
    final branch = head.substring(prefix.length).trim();
    return branch.isEmpty ? null : branch;
  } catch (_) {
    return null;
  }
}

/// The folder that holds [path], for both `/` and `\` separators.
String _parentOf(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf('\\');
  final index = slash > backslash ? slash : backslash;
  return index <= 0 ? path : path.substring(0, index);
}
