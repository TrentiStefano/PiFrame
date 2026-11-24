import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import '../runtime/harness_mode.dart';
import '../platform/widget_test_binding.dart';
// The real taskbar calls Win32 through dart:ffi, which the web build lacks.
import 'windows_taskbar_stub.dart' if (dart.library.ffi) 'windows_taskbar.dart';

enum DesktopIndicatorStatus { idle, working, unread }

class DesktopNotificationService {
  static final DesktopNotificationService instance = DesktopNotificationService._();

  DesktopNotificationService._();

  @visibleForTesting
  DesktopNotificationService.forTesting();

  bool _initialized = false;
  DesktopIndicatorStatus _indicatorStatus = DesktopIndicatorStatus.idle;
  DesktopIndicatorStatus get indicatorStatus => _indicatorStatus;
  void Function(String sessionId)? onNotificationClicked;

  bool get isSupported =>
      !kIsWeb && !isWidgetTestBinding && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  int? _windowsHwnd;

  Future<int> _getWindowsHwnd() async {
    if (_windowsHwnd != null && _windowsHwnd != 0) return _windowsHwnd!;
    try {
      _windowsHwnd = await windowManager.getId();
    } catch (_) {
      _windowsHwnd = 0;
    }
    return _windowsHwnd ?? 0;
  }

  Future<void> updateIndicatorStatus(DesktopIndicatorStatus status) async {
    if (_indicatorStatus == status) return;
    _indicatorStatus = status;

    if (!isSupported || isHarnessMode) return;

    try {
      switch (status) {
        case DesktopIndicatorStatus.working:
          if (Platform.isWindows) {
            final hwnd = await _getWindowsHwnd();
            WindowsTaskbar.instance.setProgressState(hwnd, WindowsTaskbarProgressState.indeterminate);
          } else if (Platform.isMacOS) {
            await windowManager.setBadgeLabel('⋯');
            await windowManager.setProgressBar(0.5);
          }
          await windowManager.setTitle('● PiFrame');
          break;

        case DesktopIndicatorStatus.unread:
          if (Platform.isWindows) {
            final hwnd = await _getWindowsHwnd();
            WindowsTaskbar.instance.setProgressValue(hwnd, 100, 100);
            WindowsTaskbar.instance.setProgressState(hwnd, WindowsTaskbarProgressState.normal);
          } else if (Platform.isMacOS) {
            await windowManager.setProgressBar(-1.0);
            await windowManager.setBadgeLabel('•');
          }
          await windowManager.setTitle('• PiFrame');
          break;

        case DesktopIndicatorStatus.idle:
          if (Platform.isWindows) {
            final hwnd = await _getWindowsHwnd();
            WindowsTaskbar.instance.setProgressState(hwnd, WindowsTaskbarProgressState.noProgress);
          } else if (Platform.isMacOS) {
            await windowManager.setProgressBar(-1.0);
            await windowManager.setBadgeLabel(null);
          }
          await windowManager.setTitle('PiFrame');
          break;
      }
    } catch (e) {
      debugPrint('Failed to update desktop indicator: $e');
    }
  }

  Future<void> initialize() async {
    if (!isSupported || _initialized) return;
    try {
      await localNotifier.setup(appName: 'PiFrame', shortcutPolicy: ShortcutPolicy.requireCreate);
      _initialized = true;
    } catch (e) {
      debugPrint('LocalNotifier initialization failed: $e');
    }
  }

  Future<bool> checkIsAppFocused(bool fallbackState) async {
    if (isHarnessMode || !isSupported) return fallbackState;
    try {
      return await windowManager.isFocused();
    } catch (_) {
      return fallbackState;
    }
  }

  Future<void> showNotification({required String title, required String body, String? sessionId}) async {
    if (!isSupported || !_initialized) return;
    try {
      final notification = LocalNotification(title: title, body: body);

      notification.onClick = () {
        if (!isHarnessMode) {
          try {
            unawaited(windowManager.show());
            unawaited(windowManager.focus());
          } catch (_) {}
        }
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
