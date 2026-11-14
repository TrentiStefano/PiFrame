import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User preference for reduced motion. It is combined with the OS
/// "remove animations" setting in `PiFrameApp` (see `main.dart`), so every
/// `MediaQuery.disableAnimationsOf` check in the app honours both.
@immutable
class ReducedMotionSettings {
  final bool enabled;

  const ReducedMotionSettings({this.enabled = false});

  ReducedMotionSettings copyWith({bool? enabled}) =>
      ReducedMotionSettings(enabled: enabled ?? this.enabled);

  Map<String, dynamic> toJson() => {'enabled': enabled};

  factory ReducedMotionSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReducedMotionSettings();
    final raw = json['enabled'];
    return ReducedMotionSettings(enabled: raw is bool ? raw : false);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReducedMotionSettings && enabled == other.enabled;

  @override
  int get hashCode => enabled.hashCode;
}

class ReducedMotionSettingsNotifier extends StateNotifier<ReducedMotionSettings> {
  final File? _customStorageFile;

  ReducedMotionSettingsNotifier({File? storageFile})
      : _customStorageFile = storageFile,
        super(const ReducedMotionSettings()) {
    _load();
  }

  File? _storageFile() {
    if (_customStorageFile != null) return _customStorageFile;
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.piframe');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}/reduced_motion_settings.json');
    } catch (_) {
      return null;
    }
  }

  void _load() {
    final file = _storageFile();
    if (file == null || !file.existsSync()) return;
    try {
      final map = jsonDecode(file.readAsStringSync());
      if (map is Map<String, dynamic>) {
        state = ReducedMotionSettings.fromJson(map);
      }
    } catch (_) {}
  }

  void _save() {
    final file = _storageFile();
    if (file == null) return;
    try {
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(state.toJson()));
    } catch (_) {}
  }

  void setEnabled(bool value) {
    if (state.enabled == value) return;
    state = state.copyWith(enabled: value);
    _save();
  }
}

final reducedMotionSettingsProvider =
    StateNotifierProvider<ReducedMotionSettingsNotifier, ReducedMotionSettings>(
  (ref) => ReducedMotionSettingsNotifier(),
);
