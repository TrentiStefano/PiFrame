import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Remembers, per install, that the app intro has played (welcome stagger and,
/// later, the startup overlay of plan task 7.8). Stored as `~/.piframe/app_first_run.json`,
/// like the other preference files. It is separate from `first_run.json`, which
/// tracks only the Pi CLI install prompt and stays unset for users who already have Pi.
///
/// Disabled under tests and on the web unless a file is injected: [consumeIntro]
/// then returns false, so no intro plays.
class AppFirstRunStore {
  AppFirstRunStore._();
  static final AppFirstRunStore instance = AppFirstRunStore._();

  File? _customFile;

  @visibleForTesting
  void setStorageFileForTesting(File? file) => _customFile = file;

  File? _storageFile() {
    if (_customFile != null) return _customFile;
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows ? (env['USERPROFILE'] ?? 'C:\\Users\\Default') : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.piframe');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}/app_first_run.json');
    } catch (_) {
      return null;
    }
  }

  /// Returns true exactly once per install: the first call marks the intro as
  /// played and returns true; later calls return false.
  bool consumeIntro() {
    final file = _storageFile();
    if (file == null) return false;
    try {
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map && decoded['introPlayed'] == true) return false;
      }
      file.writeAsStringSync(jsonEncode({'introPlayed': true}));
      return true;
    } catch (_) {
      return false;
    }
  }
}

final appFirstRunStoreProvider = Provider<AppFirstRunStore>((ref) {
  return AppFirstRunStore.instance;
});
