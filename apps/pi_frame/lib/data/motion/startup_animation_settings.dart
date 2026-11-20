import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../first_run/app_first_run_store.dart';

/// Preference "Animazione di avvio": when on, the 1.4 s startup assemble
/// animation (with its audio) plays on every launch, not only on the first run.
/// Off by default: later launches show the 620 ms launch reveal.
@immutable
class StartupAnimationSettings {
  final bool enabled;

  const StartupAnimationSettings({this.enabled = false});

  StartupAnimationSettings copyWith({bool? enabled}) =>
      StartupAnimationSettings(enabled: enabled ?? this.enabled);

  Map<String, dynamic> toJson() => {'enabled': enabled};

  factory StartupAnimationSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const StartupAnimationSettings();
    final raw = json['enabled'];
    return StartupAnimationSettings(enabled: raw is bool ? raw : false);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StartupAnimationSettings && enabled == other.enabled;

  @override
  int get hashCode => enabled.hashCode;
}

class StartupAnimationSettingsNotifier
    extends StateNotifier<StartupAnimationSettings> {
  final File? _customStorageFile;

  StartupAnimationSettingsNotifier({File? storageFile})
      : _customStorageFile = storageFile,
        super(const StartupAnimationSettings()) {
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
      return File('${dir.path}/startup_animation_settings.json');
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
        state = StartupAnimationSettings.fromJson(map);
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

final startupAnimationSettingsProvider = StateNotifierProvider<
    StartupAnimationSettingsNotifier, StartupAnimationSettings>(
  (ref) => StartupAnimationSettingsNotifier(),
);

/// Whether this launch is the first run. Consumed once per provider scope
/// (the store is marked played), so the startup animation and the welcome entrance agree.
final appIntroFirstRunProvider = Provider<bool>(
  (ref) => AppFirstRunStore.instance.consumeIntro(),
);

/// True when the startup assemble animation plays on this launch: the first
/// run, or every launch while "Animazione di avvio" is on.
final startupIntroPlaysProvider = Provider<bool>((ref) {
  if (ref.watch(appIntroFirstRunProvider)) return true;
  return ref.watch(startupAnimationSettingsProvider).enabled;
});
