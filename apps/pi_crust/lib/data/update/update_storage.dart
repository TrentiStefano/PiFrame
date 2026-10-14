import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../domain/update/update_models.dart';

abstract class UpdateStorage {
  Future<UpdateSettings> loadSettings();
  Future<void> saveSettings(UpdateSettings settings);
}

class FileUpdateStorage implements UpdateStorage {
  final File? _customFile;

  FileUpdateStorage([this._customFile]);

  File? _resolveFile() {
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
      return File('${dir.path}/update_settings.json');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<UpdateSettings> loadSettings() async {
    final file = _resolveFile();
    if (file != null && await file.exists()) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content);
        if (json is Map<String, dynamic>) {
          return UpdateSettings.fromJson(json);
        }
      } catch (_) {}
    }
    return const UpdateSettings();
  }

  @override
  Future<void> saveSettings(UpdateSettings settings) async {
    final file = _resolveFile();
    if (file != null) {
      try {
        await file.writeAsString(jsonEncode(settings.toJson()));
      } catch (_) {}
    }
  }
}

class MemoryUpdateStorage implements UpdateStorage {
  UpdateSettings _settings;

  MemoryUpdateStorage([this._settings = const UpdateSettings()]);

  @override
  Future<UpdateSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(UpdateSettings settings) async {
    _settings = settings;
  }
}
