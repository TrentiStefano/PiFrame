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

  /// true or false forces reduced motion on or off, over both the OS setting
  /// and the app's "Reduce animations" preference. null follows them.
  final bool? reduceMotion;
  final Brightness? brightness;

  HarnessMediaOverrides copyWith({
    double? textScale,
    bool? reduceMotion,
    Brightness? brightness,
    bool followSystemMotion = false,
  }) => HarnessMediaOverrides(
    textScale: textScale ?? this.textScale,
    reduceMotion: followSystemMotion ? null : reduceMotion ?? this.reduceMotion,
    brightness: brightness ?? this.brightness,
  );
}

/// What a harness run starts with, and what `media --reset` restores:
/// animations on, so agents can capture and study the app's motion whatever
/// the machine's or the harness home's reduce-motion setting.
const kHarnessDefaultMediaOverrides = HarnessMediaOverrides(reduceMotion: false);

final ValueNotifier<HarnessMediaOverrides> harnessMediaOverrides =
    ValueNotifier(kHarnessDefaultMediaOverrides);

void setHarnessMediaOverrides({
  double? textScale,
  bool? reduceMotion,
  Brightness? brightness,
  bool followSystemMotion = false,
  bool reset = false,
}) {
  if (!_harnessMode) return;
  harnessMediaOverrides.value = reset
      ? kHarnessDefaultMediaOverrides
      : harnessMediaOverrides.value.copyWith(
          textScale: textScale,
          reduceMotion: reduceMotion,
          brightness: brightness,
          followSystemMotion: followSystemMotion,
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
  // A harness choice wins: an earlier run that switched on "Reduce
  // animations" in Settings must not hide every animation from later runs.
  disableAnimations: harnessEnabled && overrides.reduceMotion != null
      ? overrides.reduceMotion!
      : media.disableAnimations || reduceMotionPreference,
  platformBrightness: harnessEnabled
      ? overrides.brightness ?? media.platformBrightness
      : media.platformBrightness,
);

void enableHarnessMode() {
  _harnessMode = true;
}
