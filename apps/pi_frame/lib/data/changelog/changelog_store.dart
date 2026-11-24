import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/file_system_service.dart';
import '../platform/runtime_mode.dart';

/// Remembers the last PiFrame version for which the user has seen the changelog popup.
/// Stored as `~/.piframe/changelog_state.json`.
class ChangelogStore {
  ChangelogStore._();
  static final ChangelogStore instance = ChangelogStore._();

  FileSystemService _files = const IoFileSystemService();
  String? _customStatePath;
  String? _customFirstRunPath;

  /// Points the store at [files] and at the two preference paths. Calling it with no arguments
  /// restores the home-directory defaults.
  @visibleForTesting
  void setStorageForTesting({FileSystemService? files, String? statePath, String? firstRunPath}) {
    _files = files ?? const IoFileSystemService();
    _customStatePath = statePath;
    _customFirstRunPath = firstRunPath;
  }

  /// `~/.piframe/[name]`, or null on the web build and under tests (no preference files there).
  static String? _homeFile(String name) {
    if (!usesHomeDirectoryStorage) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows ? (env['USERPROFILE'] ?? 'C:\\Users\\Default') : (env['HOME'] ?? '/tmp');
      return '$home/.piframe/$name';
    } catch (error) {
      debugPrint('ChangelogStore could not resolve the home folder: $error');
      return null;
    }
  }

  String? get _statePath => _customStatePath ?? _homeFile('changelog_state.json');

  String? get _firstRunPath => _customFirstRunPath ?? _homeFile('app_first_run.json');

  String? getLastSeenVersion() {
    final path = _statePath;
    if (path == null || !_files.fileExistsSync(path)) return null;
    try {
      final content = _files.readTextSync(path);
      if (content == null) return null;
      final data = jsonDecode(content);
      if (data is Map && data['lastSeenVersion'] != null) {
        return data['lastSeenVersion'].toString();
      }
    } catch (error) {
      debugPrint('ChangelogStore could not read $path: $error');
    }
    return null;
  }

  void setLastSeenVersion(String version) {
    final path = _statePath;
    if (path == null) return;
    try {
      _files.writeTextSync(path, jsonEncode({'lastSeenVersion': version}));
    } catch (error) {
      debugPrint('ChangelogStore could not write $path: $error');
    }
  }

  /// Determines whether the changelog popup should be displayed for [currentVersion].
  ///
  /// Returns `true` if:
  /// - The user previously saw a different version (`lastSeenVersion != currentVersion`).
  /// - Or this is an existing installation upgrading to a release with this feature
  ///   for the first time (i.e. `lastSeenVersion == null` but `app_first_run.json` exists).
  ///
  /// Returns `false` for:
  /// - Completely fresh installs where `app_first_run.json` does not exist yet (marking
  ///   current version as seen so the popup is not shown on initial install).
  /// - When the user has already seen the popup for [currentVersion].
  bool shouldShowChangelog(String currentVersion) {
    final lastSeen = getLastSeenVersion();
    if (lastSeen == currentVersion) {
      return false;
    }

    if (lastSeen == null) {
      final firstRunPath = _firstRunPath;
      final isExistingInstall = firstRunPath != null && _files.fileExistsSync(firstRunPath);
      if (!isExistingInstall) {
        // Fresh install: mark current version as seen so the popup doesn't appear immediately.
        setLastSeenVersion(currentVersion);
        return false;
      }
    }

    return true;
  }
}

final changelogStoreProvider = Provider<ChangelogStore>((ref) {
  return ChangelogStore.instance;
});
