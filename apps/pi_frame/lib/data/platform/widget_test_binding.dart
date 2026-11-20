import 'package:flutter/widgets.dart';

/// True when the app runs under a Flutter test binding (`flutter test`).
///
/// Widgets use it to skip endless animations, native views and OS services
/// that cannot run, or never settle, in widget tests.
bool get isWidgetTestBinding =>
    WidgetsBinding.instance.runtimeType.toString().contains('Test');
