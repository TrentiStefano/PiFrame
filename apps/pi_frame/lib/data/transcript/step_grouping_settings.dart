import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session/transcript_grouping.dart';

@immutable
class StepGroupingSettings {
  final StepGroupingMode mode;
  final bool autoCollapse;
  final bool showIntermediateAnswers;

  const StepGroupingSettings({
    this.mode = StepGroupingMode.withThinking,
    this.autoCollapse = true,
    this.showIntermediateAnswers = true,
  });

  StepGroupingSettings copyWith({StepGroupingMode? mode, bool? autoCollapse, bool? showIntermediateAnswers}) {
    return StepGroupingSettings(
      mode: mode ?? this.mode,
      autoCollapse: autoCollapse ?? this.autoCollapse,
      showIntermediateAnswers: showIntermediateAnswers ?? this.showIntermediateAnswers,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'autoCollapse': autoCollapse,
    'showIntermediateAnswers': showIntermediateAnswers,
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
    final parsedAutoCollapse = rawAutoCollapse is bool ? rawAutoCollapse : true;

    final rawShowIntermediateAnswers = json['showIntermediateAnswers'];
    final parsedShowIntermediateAnswers = rawShowIntermediateAnswers is bool ? rawShowIntermediateAnswers : true;

    return StepGroupingSettings(
      mode: parsedMode,
      autoCollapse: parsedAutoCollapse,
      showIntermediateAnswers: parsedShowIntermediateAnswers,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepGroupingSettings &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          autoCollapse == other.autoCollapse &&
          showIntermediateAnswers == other.showIntermediateAnswers;

  @override
  int get hashCode => Object.hash(mode, autoCollapse, showIntermediateAnswers);

  @override
  String toString() =>
      'StepGroupingSettings(mode: ${mode.name}, autoCollapse: $autoCollapse, showIntermediateAnswers: $showIntermediateAnswers)';
}

class StepGroupingSettingsNotifier extends StateNotifier<StepGroupingSettings> {
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
      final home = Platform.isWindows ? (env['USERPROFILE'] ?? 'C:\\Users\\Default') : (env['HOME'] ?? '/tmp');
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

  void setShowIntermediateAnswers(bool showIntermediateAnswers) {
    if (state.showIntermediateAnswers != showIntermediateAnswers) {
      state = state.copyWith(showIntermediateAnswers: showIntermediateAnswers);
      _save();
    }
  }
}

final stepGroupingSettingsProvider = StateNotifierProvider<StepGroupingSettingsNotifier, StepGroupingSettings>((ref) {
  return StepGroupingSettingsNotifier();
});
