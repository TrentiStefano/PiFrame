import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads facts about the host that features branch on: whether this is the
/// web build, the operating system and the value of an environment variable.
abstract class HostEnvironmentService {
  bool get isWeb;

  /// True on the Windows desktop build; false on the web build.
  bool get isWindows;

  /// `windows`, `macos`, `linux` (or another Dart platform name). `web` in the browser build.
  String get operatingSystem;

  /// The value of environment variable [name], or null when it is not set.
  String? variable(String name);
}

class PlatformHostEnvironmentService implements HostEnvironmentService {
  const PlatformHostEnvironmentService();

  @override
  bool get isWeb => kIsWeb;

  @override
  bool get isWindows => !kIsWeb && Platform.isWindows;

  @override
  String get operatingSystem => kIsWeb ? 'web' : Platform.operatingSystem;

  @override
  String? variable(String name) => kIsWeb ? null : Platform.environment[name];
}

final hostEnvironmentServiceProvider = Provider<HostEnvironmentService>(
  (ref) => const PlatformHostEnvironmentService(),
);
