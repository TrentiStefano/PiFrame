import 'package:flutter/material.dart';

/// Whether this process was started through the developer-only UI harness.
///
/// Set before bootstrapping the app so desktop services can avoid user-facing
/// side effects such as persisting window geometry or activating the window.
bool _harnessMode = false;

bool get isHarnessMode => _harnessMode;

class HarnessMediaOverrides {
  const HarnessMediaOverrides({
    this.textScale,
    this.reduceMotion,
    this.brightness,
  });

  final double? textScale;
  final bool? reduceMotion;
  final Brightness? brightness;

  HarnessMediaOverrides copyWith({
    double? textScale,
    bool? reduceMotion,
    Brightness? brightness,
  }) => HarnessMediaOverrides(
    textScale: textScale ?? this.textScale,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    brightness: brightness ?? this.brightness,
  );
}

final ValueNotifier<HarnessMediaOverrides> harnessMediaOverrides =
    ValueNotifier(const HarnessMediaOverrides());

void setHarnessMediaOverrides({
  double? textScale,
  bool? reduceMotion,
  Brightness? brightness,
  bool reset = false,
}) {
  if (!_harnessMode) return;
  harnessMediaOverrides.value = reset
      ? const HarnessMediaOverrides()
      : harnessMediaOverrides.value.copyWith(
          textScale: textScale,
          reduceMotion: reduceMotion,
          brightness: brightness,
        );
}

MediaQueryData applyHarnessMediaOverrides(
  MediaQueryData media, {
  required bool harnessEnabled,
  required bool reduceMotionPreference,
  HarnessMediaOverrides overrides = const HarnessMediaOverrides(),
}) => media.copyWith(
  textScaler: harnessEnabled && overrides.textScale != null
      ? TextScaler.linear(overrides.textScale!)
      : media.textScaler,
  disableAnimations:
      media.disableAnimations ||
      reduceMotionPreference ||
      (harnessEnabled && (overrides.reduceMotion ?? false)),
  platformBrightness: harnessEnabled
      ? overrides.brightness ?? media.platformBrightness
      : media.platformBrightness,
);

void enableHarnessMode() {
  _harnessMode = true;
}
