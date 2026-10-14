import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

abstract class ThemeStorage {
  String? loadActiveThemeIdSync();
  Future<String?> loadActiveThemeId();
  Future<void> saveActiveThemeId(String themeId);
  Future<File?> saveUserThemeFile(String filename, String content);
  Directory? resolveUserThemesDir();
}

class FileThemeStorage implements ThemeStorage {
  final File? _customFile;
  final Directory? _customThemesDir;

  FileThemeStorage([this._customFile, this._customThemesDir]);

  File? _resolveSettingsFile() {
    if (_customFile != null) return _customFile;
    if (kIsWeb) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.pi-crust');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}/theme_settings.json');
    } catch (_) {
      return null;
    }
  }

  @override
  Directory? resolveUserThemesDir() {
    if (_customThemesDir != null) return _customThemesDir;
    if (kIsWeb) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.pi-crust/themes');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  @override
  String? loadActiveThemeIdSync() {
    final file = _resolveSettingsFile();
    if (file != null && file.existsSync()) {
      try {
        final content = file.readAsStringSync();
        final json = jsonDecode(content);
        if (json is Map && json['activeThemeId'] is String) {
          final id = json['activeThemeId'] as String;
          if (id.trim().isNotEmpty) return id.trim();
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<String?> loadActiveThemeId() async {
    return loadActiveThemeIdSync();
  }

  @override
  Future<void> saveActiveThemeId(String themeId) async {
    final file = _resolveSettingsFile();
    if (file != null) {
      try {
        await file.writeAsString(jsonEncode({'activeThemeId': themeId}));
      } catch (_) {}
    }
  }

  @override
  Future<File?> saveUserThemeFile(String filename, String content) async {
    final dir = resolveUserThemesDir();
    if (dir == null) return null;
    try {
      final sanitizedName = filename.endsWith('.json') ? filename : '$filename.json';
      final file = File('${dir.path}/$sanitizedName');
      await file.writeAsString(content);
      return file;
    } catch (_) {
      return null;
    }
  }
}

class MemoryThemeStorage implements ThemeStorage {
  String? _activeThemeId;
  final Map<String, String> userThemes = {};

  MemoryThemeStorage([this._activeThemeId]);

  @override
  String? loadActiveThemeIdSync() => _activeThemeId;

  @override
  Future<String?> loadActiveThemeId() async => _activeThemeId;

  @override
  Future<void> saveActiveThemeId(String themeId) async {
    _activeThemeId = themeId;
  }

  @override
  Future<File?> saveUserThemeFile(String filename, String content) async {
    userThemes[filename] = content;
    return null;
  }

  @override
  Directory? resolveUserThemesDir() => null;
}
