import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session/transcript_grouping.dart';

@immutable
class StepGroupingSettings {
  final StepGroupingMode mode;
  final bool autoCollapse;

  const StepGroupingSettings({
    this.mode = StepGroupingMode.withThinking,
    this.autoCollapse = true,
  });

  StepGroupingSettings copyWith({
    StepGroupingMode? mode,
    bool? autoCollapse,
  }) {
    return StepGroupingSettings(
      mode: mode ?? this.mode,
      autoCollapse: autoCollapse ?? this.autoCollapse,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'autoCollapse': autoCollapse,
  };

  factory StepGroupingSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const StepGroupingSettings();

    final rawMode = json['mode'];
    StepGroupingMode parsedMode = StepGroupingMode.withThinking;
    if (rawMode is String) {
      parsedMode = StepGroupingMode.values.firstWhere(
        (m) => m.name.toLowerCase() == rawMode.toLowerCase().trim(),
        orElse: () => StepGroupingMode.withThinking,
      );
    }

    final rawAutoCollapse = json['autoCollapse'];
    final parsedAutoCollapse =
        rawAutoCollapse is bool ? rawAutoCollapse : true;

    return StepGroupingSettings(
      mode: parsedMode,
      autoCollapse: parsedAutoCollapse,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepGroupingSettings &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          autoCollapse == other.autoCollapse;

  @override
  int get hashCode => Object.hash(mode, autoCollapse);

  @override
  String toString() =>
      'StepGroupingSettings(mode: ${mode.name}, autoCollapse: $autoCollapse)';
}

class StepGroupingSettingsNotifier
    extends StateNotifier<StepGroupingSettings> {
  final File? _customStorageFile;

  StepGroupingSettingsNotifier({File? storageFile})
      : _customStorageFile = storageFile,
        super(const StepGroupingSettings()) {
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
      return File('${dir.path}/step_grouping_settings.json');
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
          state = StepGroupingSettings.fromJson(map);
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

  void setMode(StepGroupingMode mode) {
    if (state.mode != mode) {
      state = state.copyWith(mode: mode);
      _save();
    }
  }

  void setAutoCollapse(bool autoCollapse) {
    if (state.autoCollapse != autoCollapse) {
      state = state.copyWith(autoCollapse: autoCollapse);
      _save();
    }
  }
}

final stepGroupingSettingsProvider = StateNotifierProvider<
    StepGroupingSettingsNotifier, StepGroupingSettings>((ref) {
  return StepGroupingSettingsNotifier();
});
