import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Remembers the last PiFrame version for which the user has seen the changelog popup.
/// Stored as `~/.piframe/changelog_state.json`.
class ChangelogStore {
  ChangelogStore._();
  static final ChangelogStore instance = ChangelogStore._();

  File? _customFile;
  File? _customFirstRunFile;

  @visibleForTesting
  void setStorageFileForTesting(File? file) => _customFile = file;

  @visibleForTesting
  void setFirstRunFileForTesting(File? file) => _customFirstRunFile = file;

  File? _storageFile() {
    if (_customFile != null) return _customFile;
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows ? (env['USERPROFILE'] ?? 'C:\\Users\\Default') : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.piframe');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}/changelog_state.json');
    } catch (_) {
      return null;
    }
  }

  File? _resolveFirstRunFile() {
    if (_customFirstRunFile != null) return _customFirstRunFile;
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows ? (env['USERPROFILE'] ?? 'C:\\Users\\Default') : (env['HOME'] ?? '/tmp');
      return File('$home/.piframe/app_first_run.json');
    } catch (_) {
      return null;
    }
  }

  String? getLastSeenVersion() {
    final file = _storageFile();
    if (file == null || !file.existsSync()) return null;
    try {
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      if (data is Map && data['lastSeenVersion'] != null) {
        return data['lastSeenVersion'].toString();
      }
    } catch (_) {}
    return null;
  }

  void setLastSeenVersion(String version) {
    final file = _storageFile();
    if (file == null) return;
    try {
      file.writeAsStringSync(jsonEncode({'lastSeenVersion': version}));
    } catch (_) {}
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
      final firstRunFile = _resolveFirstRunFile();
      final isExistingInstall = firstRunFile != null && firstRunFile.existsSync();
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
