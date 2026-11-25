import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/update/update_models.dart';
import '../platform/runtime_mode.dart';

/// The platform this build runs on, as release installers are chosen for it.
ReleasePlatform currentReleasePlatform() {
  if (kIsWeb) return ReleasePlatform.web;
  try {
    if (isRunningUnderTests) {
      return _fromTarget(defaultTargetPlatform);
    }
    if (Platform.isWindows) return ReleasePlatform.windows;
    if (Platform.isMacOS) return ReleasePlatform.macOS;
    if (Platform.isLinux) return ReleasePlatform.linux;
  } catch (_) {}
  return _fromTarget(defaultTargetPlatform);
}

/// The CPU architecture named in the Dart VM version string, `arm64` or `x64`.
String currentReleaseArch() {
  try {
    final v = Platform.version.toLowerCase();
    if (v.contains('arm64') || v.contains('aarch64')) return 'arm64';
    if (v.contains('x64') || v.contains('x86_64')) return 'x64';
  } catch (_) {}
  return 'x64';
}

ReleasePlatform _fromTarget(TargetPlatform platform) => switch (platform) {
  TargetPlatform.windows => ReleasePlatform.windows,
  TargetPlatform.macOS => ReleasePlatform.macOS,
  TargetPlatform.linux => ReleasePlatform.linux,
  _ => ReleasePlatform.other,
};
