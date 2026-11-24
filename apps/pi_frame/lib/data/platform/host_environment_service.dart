import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads facts about the host that features branch on: whether this is the
/// web build, the operating system, the working directory and environment variables.
abstract class HostEnvironmentService {
  bool get isWeb;

  /// `windows`, `macos`, `linux` (or another Dart platform name). `web` in the browser build.
  String get operatingSystem;

  /// The directory the app runs from. Empty in the browser build.
  String get currentDirectory;

  /// The value of environment variable [name], or null when it is not set.
  String? variable(String name);
}

class PlatformHostEnvironmentService implements HostEnvironmentService {
  const PlatformHostEnvironmentService();

  @override
  bool get isWeb => kIsWeb;

  @override
  String get operatingSystem => kIsWeb ? 'web' : Platform.operatingSystem;

  @override
  String get currentDirectory => kIsWeb ? '' : Directory.current.path;

  @override
  String? variable(String name) => kIsWeb ? null : Platform.environment[name];
}

final hostEnvironmentServiceProvider = Provider<HostEnvironmentService>(
  (ref) => const PlatformHostEnvironmentService(),
);
