import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_win_floating/webview.dart';

import 'runtime_mode.dart';
import 'widget_test_binding.dart';

/// What an embedded web view reports while it navigates.
class EmbeddedWebViewEvents {
  final void Function(String url)? onPageStarted;
  final void Function(String url)? onPageFinished;
  final void Function(String? url)? onUrlChange;
  final void Function(String title)? onTitleChanged;
  final void Function(String description)? onLoadError;

  const EmbeddedWebViewEvents({
    this.onPageStarted,
    this.onPageFinished,
    this.onUrlChange,
    this.onTitleChanged,
    this.onLoadError,
  });
}

/// A native web view shown inside the browser pane.
abstract class EmbeddedWebView {
  /// The widget that shows the page.
  Widget get view;

  Future<void> loadRequest(Uri uri);

  Future<void> setVisibility(bool visible);

  Future<String?> currentUrl();

  Future<String?> getTitle();

  Future<bool> canGoBack();

  Future<void> goBack();

  Future<bool> canGoForward();

  Future<void> goForward();

  Future<void> reload();

  Future<void> openDevTools();

  Future<void> dispose();
}

/// Capability of the embedded (in-app) browser on this platform.
abstract class EmbeddedBrowserService {
  /// True when the native WebView can be shown here. False means the browser
  /// falls back to its own rendering and links open externally.
  bool get isNativeSupported;

  /// A new native web view that reports its navigation to [events]. Only call when [isNativeSupported].
  EmbeddedWebView createWebView(EmbeddedWebViewEvents events);
}

class PlatformEmbeddedBrowserService implements EmbeddedBrowserService {
  const PlatformEmbeddedBrowserService();

  @override
  bool get isNativeSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows && !_isFlutterTest() && !isWidgetTestBinding;

  @override
  EmbeddedWebView createWebView(EmbeddedWebViewEvents events) => _WinEmbeddedWebView(events);
}

bool _isFlutterTest() => !kIsWeb && isRunningUnderTests;

class _WinEmbeddedWebView implements EmbeddedWebView {
  _WinEmbeddedWebView(EmbeddedWebViewEvents events) : _controller = WinWebViewController() {
    unawaited(
      _controller.setNavigationDelegate(
        WinNavigationDelegate(
          onPageStarted: events.onPageStarted,
          onPageFinished: events.onPageFinished,
          onUrlChange: (change) => events.onUrlChange?.call(change.url),
          onPageTitleChanged: events.onTitleChanged,
          onWebResourceError: (error) => events.onLoadError?.call(error.description),
        ),
      ),
    );
  }

  final WinWebViewController _controller;

  @override
  Widget get view => WinWebViewWidget(controller: _controller);

  @override
  Future<void> loadRequest(Uri uri) => _controller.loadRequest(uri);

  @override
  Future<void> setVisibility(bool visible) => _controller.setVisibility(visible);

  @override
  Future<String?> currentUrl() => _controller.currentUrl();

  @override
  Future<String?> getTitle() => _controller.getTitle();

  @override
  Future<bool> canGoBack() => _controller.canGoBack();

  @override
  Future<void> goBack() => _controller.goBack();

  @override
  Future<bool> canGoForward() => _controller.canGoForward();

  @override
  Future<void> goForward() => _controller.goForward();

  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<void> openDevTools() => _controller.openDevTools();

  @override
  Future<void> dispose() => _controller.dispose();
}

final embeddedBrowserServiceProvider = Provider<EmbeddedBrowserService>(
  (ref) => const PlatformEmbeddedBrowserService(),
);
