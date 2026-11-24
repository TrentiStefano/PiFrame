import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads facts about the host that features branch on: whether this is the
/// web build and the value of an environment variable.
abstract class HostEnvironmentService {
  bool get isWeb;

  /// The value of environment variable [name], or null when it is not set.
  String? variable(String name);
}

class PlatformHostEnvironmentService implements HostEnvironmentService {
  const PlatformHostEnvironmentService();

  @override
  bool get isWeb => kIsWeb;

  @override
  String? variable(String name) => kIsWeb ? null : Platform.environment[name];
}

final hostEnvironmentServiceProvider = Provider<HostEnvironmentService>(
  (ref) => const PlatformHostEnvironmentService(),
);
