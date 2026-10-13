import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

class DesktopNotificationService {
  static final DesktopNotificationService instance =
      DesktopNotificationService._();

  DesktopNotificationService._();

  @visibleForTesting
  DesktopNotificationService.forTesting();

  bool _initialized = false;
  void Function(String sessionId)? onNotificationClicked;

  bool get isSupported =>
      !kIsWeb &&
      !WidgetsBinding.instance.runtimeType.toString().contains('Test') &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> initialize() async {
    if (!isSupported || _initialized) return;
    try {
      await localNotifier.setup(
        appName: 'Pi-Crust',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _initialized = true;
    } catch (e) {
      debugPrint('LocalNotifier initialization failed: $e');
    }
  }

  Future<bool> checkIsAppFocused(bool fallbackState) async {
    if (!isSupported) return fallbackState;
    try {
      return await windowManager.isFocused();
    } catch (_) {
      return fallbackState;
    }
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? sessionId,
  }) async {
    if (!isSupported || !_initialized) return;
    try {
      final notification = LocalNotification(
        title: title,
        body: body,
      );

      notification.onClick = () {
        try {
          windowManager.show();
          windowManager.focus();
        } catch (_) {}
        if (sessionId != null) {
          onNotificationClicked?.call(sessionId);
        }
      };

      await notification.show();
    } catch (e) {
      debugPrint('Error showing system notification: $e');
    }
  }
}
