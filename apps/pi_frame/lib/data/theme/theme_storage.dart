import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ThemeSettings {
  final String activeThemeId;
  final String defaultDarkThemeId;
  final String defaultLightThemeId;
  final bool useSystemTheme;

  const ThemeSettings({
    this.activeThemeId = 'piframe-dark',
    this.defaultDarkThemeId = 'piframe-dark',
    this.defaultLightThemeId = 'piframe-light',
    this.useSystemTheme = false,
  });

  Map<String, dynamic> toJson() => {
    'activeThemeId': activeThemeId,
    'defaultDarkThemeId': defaultDarkThemeId,
    'defaultLightThemeId': defaultLightThemeId,
    'useSystemTheme': useSystemTheme,
  };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) {
    return ThemeSettings(
      activeThemeId:
          (json['activeThemeId'] as String?)?.trim().isNotEmpty == true
              ? (json['activeThemeId'] as String).trim()
              : 'piframe-dark',
      defaultDarkThemeId:
          (json['defaultDarkThemeId'] as String?)?.trim().isNotEmpty == true
              ? (json['defaultDarkThemeId'] as String).trim()
              : 'piframe-dark',
      defaultLightThemeId:
          (json['defaultLightThemeId'] as String?)?.trim().isNotEmpty == true
              ? (json['defaultLightThemeId'] as String).trim()
              : 'piframe-light',
      useSystemTheme: json['useSystemTheme'] as bool? ?? false,
    );
  }

  ThemeSettings copyWith({
    String? activeThemeId,
    String? defaultDarkThemeId,
    String? defaultLightThemeId,
    bool? useSystemTheme,
  }) {
    return ThemeSettings(
      activeThemeId: activeThemeId ?? this.activeThemeId,
      defaultDarkThemeId: defaultDarkThemeId ?? this.defaultDarkThemeId,
      defaultLightThemeId: defaultLightThemeId ?? this.defaultLightThemeId,
      useSystemTheme: useSystemTheme ?? this.useSystemTheme,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeSettings &&
          runtimeType == other.runtimeType &&
          activeThemeId == other.activeThemeId &&
          defaultDarkThemeId == other.defaultDarkThemeId &&
          defaultLightThemeId == other.defaultLightThemeId &&
          useSystemTheme == other.useSystemTheme;

  @override
  int get hashCode =>
      activeThemeId.hashCode ^
      defaultDarkThemeId.hashCode ^
      defaultLightThemeId.hashCode ^
      useSystemTheme.hashCode;
}

abstract class ThemeStorage {
  ThemeSettings loadSettingsSync();
  Future<ThemeSettings> loadSettings();
  Future<void> saveSettings(ThemeSettings settings);

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
      final dir = Directory('$home/.piframe');
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
      final dir = Directory('$home/.piframe/themes');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  @override
  ThemeSettings loadSettingsSync() {
    final file = _resolveSettingsFile();
    if (file != null && file.existsSync()) {
      try {
        final content = file.readAsStringSync();
        final json = jsonDecode(content);
        if (json is Map) {
          return ThemeSettings.fromJson(Map<String, dynamic>.from(json));
        }
      } catch (_) {}
    }
    return const ThemeSettings();
  }

  @override
  Future<ThemeSettings> loadSettings() async {
    return loadSettingsSync();
  }

  @override
  Future<void> saveSettings(ThemeSettings settings) async {
    final file = _resolveSettingsFile();
    if (file != null) {
      try {
        await file.writeAsString(jsonEncode(settings.toJson()));
      } catch (_) {}
    }
  }

  @override
  String? loadActiveThemeIdSync() {
    return loadSettingsSync().activeThemeId;
  }

  @override
  Future<String?> loadActiveThemeId() async {
    return loadActiveThemeIdSync();
  }

  @override
  Future<void> saveActiveThemeId(String themeId) async {
    final current = loadSettingsSync();
    await saveSettings(current.copyWith(activeThemeId: themeId));
  }

  @override
  Future<File?> saveUserThemeFile(String filename, String content) async {
    final dir = resolveUserThemesDir();
    if (dir == null) return null;
    try {
      final sanitizedName =
          filename.endsWith('.json') ? filename : '$filename.json';
      final file = File('${dir.path}/$sanitizedName');
      await file.writeAsString(content);
      return file;
    } catch (_) {
      return null;
    }
  }
}

class MemoryThemeStorage implements ThemeStorage {
  ThemeSettings _settings;
  final Map<String, String> userThemes = {};

  MemoryThemeStorage([dynamic initial])
      : _settings = initial is ThemeSettings
            ? initial
            : initial is String
                ? ThemeSettings(activeThemeId: initial)
                : const ThemeSettings();

  @override
  ThemeSettings loadSettingsSync() => _settings;

  @override
  Future<ThemeSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(ThemeSettings settings) async {
    _settings = settings;
  }

  @override
  String? loadActiveThemeIdSync() => _settings.activeThemeId;

  @override
  Future<String?> loadActiveThemeId() async => _settings.activeThemeId;

  @override
  Future<void> saveActiveThemeId(String themeId) async {
    _settings = _settings.copyWith(activeThemeId: themeId);
  }

  @override
  Future<File?> saveUserThemeFile(String filename, String content) async {
    userThemes[filename] = content;
    return null;
  }

  @override
  Directory? resolveUserThemesDir() => null;
}

