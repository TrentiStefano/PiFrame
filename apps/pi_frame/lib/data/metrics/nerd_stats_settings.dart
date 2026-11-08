import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class NerdStatsSettings {
  final bool enabled;

  const NerdStatsSettings({this.enabled = false});

  NerdStatsSettings copyWith({bool? enabled}) {
    return NerdStatsSettings(
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
  };

  factory NerdStatsSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NerdStatsSettings();
    final raw = json['enabled'];
    return NerdStatsSettings(
      enabled: raw is bool ? raw : false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NerdStatsSettings &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled;

  @override
  int get hashCode => enabled.hashCode;

  @override
  String toString() => 'NerdStatsSettings(enabled: $enabled)';
}

class NerdStatsSettingsNotifier extends StateNotifier<NerdStatsSettings> {
  final File? _customStorageFile;

  NerdStatsSettingsNotifier({File? storageFile})
      : _customStorageFile = storageFile,
        super(const NerdStatsSettings()) {
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
      return File('${dir.path}/nerd_stats_settings.json');
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
          state = NerdStatsSettings.fromJson(map);
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

  void setEnabled(bool value) {
    if (state.enabled != value) {
      state = state.copyWith(enabled: value);
      _save();
    }
  }
}

final nerdStatsSettingsProvider =
    StateNotifierProvider<NerdStatsSettingsNotifier, NerdStatsSettings>((ref) {
  return NerdStatsSettingsNotifier();
});
