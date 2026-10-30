import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Stores which workspace panes are hidden so a restart reopens the same layout.
/// Like the other ~/.piframe preference files, it is disabled under tests unless a file is injected.
class LayoutStore {
  LayoutStore._();
  static final LayoutStore instance = LayoutStore._();

  File? _customFile;

  @visibleForTesting
  void setStorageFileForTesting(File? file) => _customFile = file;

  File? _storageFile() {
    if (_customFile != null) return _customFile;
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.piframe');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}/layout.json');
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> load() {
    final file = _storageFile();
    if (file == null || !file.existsSync()) return const {};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  void save(Map<String, dynamic> layout) {
    final file = _storageFile();
    if (file == null) return;
    try {
      file.writeAsStringSync(jsonEncode(layout));
    } catch (_) {}
  }
}
