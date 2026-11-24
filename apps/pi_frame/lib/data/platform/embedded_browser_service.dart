import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widget_test_binding.dart';

/// Capability of the embedded (in-app) browser on this platform.
abstract class EmbeddedBrowserService {
  /// True when the native WebView can be shown here. False means the browser
  /// falls back to its own rendering and links open externally.
  bool get isNativeSupported;
}

class PlatformEmbeddedBrowserService implements EmbeddedBrowserService {
  const PlatformEmbeddedBrowserService();

  @override
  bool get isNativeSupported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      !isWidgetTestBinding;
}

final embeddedBrowserServiceProvider = Provider<EmbeddedBrowserService>(
  (ref) => const PlatformEmbeddedBrowserService(),
);
