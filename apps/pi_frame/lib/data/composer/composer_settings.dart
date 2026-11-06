import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class ComposerSettings {
  final bool sendWithEnter;

  const ComposerSettings({this.sendWithEnter = false});

  ComposerSettings copyWith({bool? sendWithEnter}) {
    return ComposerSettings(
      sendWithEnter: sendWithEnter ?? this.sendWithEnter,
    );
  }

  Map<String, dynamic> toJson() => {
    'sendWithEnter': sendWithEnter,
  };

  factory ComposerSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ComposerSettings();
    final raw = json['sendWithEnter'];
    return ComposerSettings(
      sendWithEnter: raw is bool ? raw : false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComposerSettings &&
          runtimeType == other.runtimeType &&
          sendWithEnter == other.sendWithEnter;

  @override
  int get hashCode => sendWithEnter.hashCode;

  @override
  String toString() => 'ComposerSettings(sendWithEnter: $sendWithEnter)';
}

class ComposerSettingsNotifier extends StateNotifier<ComposerSettings> {
  final File? _customStorageFile;

  ComposerSettingsNotifier({File? storageFile})
      : _customStorageFile = storageFile,
        super(const ComposerSettings()) {
    _load();
  }

  File? _getStorageFile() {
    if (_customStorageFile != null) return _customStorageFile;
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.piframe');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}/composer_settings.json');
    } catch (_) {
      return null;
    }
  }

  void _load() {
    final file = _getStorageFile();
    if (file != null && file.existsSync()) {
      try {
        final content = file.readAsStringSync();
        final map = jsonDecode(content);
        if (map is Map<String, dynamic>) {
          state = ComposerSettings.fromJson(map);
        }
      } catch (_) {}
    }
  }

  void _save() {
    final file = _getStorageFile();
    if (file != null) {
      try {
        final parent = file.parent;
        if (!parent.existsSync()) {
          parent.createSync(recursive: true);
        }
        file.writeAsStringSync(jsonEncode(state.toJson()));
      } catch (_) {}
    }
  }

  void setSendWithEnter(bool value) {
    if (state.sendWithEnter != value) {
      state = state.copyWith(sendWithEnter: value);
      _save();
    }
  }
}

final composerSettingsProvider =
    StateNotifierProvider<ComposerSettingsNotifier, ComposerSettings>((ref) {
  return ComposerSettingsNotifier();
});
