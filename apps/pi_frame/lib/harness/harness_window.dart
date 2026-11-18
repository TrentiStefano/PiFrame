import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

Future<void> configureHarnessWindow(Size size) async {
  await windowManager.waitUntilReadyToShow(
    WindowOptions(size: size, skipTaskbar: true, title: 'PiFrame harness'),
  );
  await windowManager.setSize(size);
  await windowManager.setPosition(const Offset(-32000, -32000));
  if (Platform.isWindows) {
    await windowManager.setSkipTaskbar(true);
    _preventWindowsActivation(await windowManager.getId());
    await windowManager.show(inactive: true);
  } else {
    await windowManager.show(inactive: true);
  }
  // The frame correction (setHarnessContentSize) runs once the app is up:
  // see main_harness.dart.
}

/// Logical size of the app's drawing area (the window minus its frame).
Size harnessContentSize() {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  return view.physicalSize / view.devicePixelRatio;
}

/// Sizes the window so the app itself gets [content] logical pixels: a
/// `--size 1920x1032` run then renders and captures exactly like a maximized
/// window on a 1080p screen with the taskbar. `setSize` sets the outer
/// window, whose frame takes some pixels, so the frame's share is measured
/// and added back. Returns the content size reached.
Future<Size> setHarnessContentSize(Size content) async {
  await windowManager.setSize(content);
  await windowManager.setPosition(const Offset(-32000, -32000));
  for (var attempt = 0; attempt < 4; attempt++) {
    await _settleViewMetrics();
    final actual = harnessContentSize();
    final dx = content.width - actual.width;
    final dy = content.height - actual.height;
    if (dx.abs() < 0.5 && dy.abs() < 0.5) return actual;
    final outer = await windowManager.getSize();
    await windowManager.setSize(Size(outer.width + dx, outer.height + dy));
    await windowManager.setPosition(const Offset(-32000, -32000));
  }
  await _settleViewMetrics();
  return harnessContentSize();
}

/// How often a resize polls the view for its new size, and for how long.
const _resizePollInterval = Duration(milliseconds: 30);
const _resizePollSteps = 20;

/// One more beat after the size changed, so a resize that lands in steps has
/// finished.
const _resizeSettleDelay = Duration(milliseconds: 60);

/// Waits until the view reports a new size after a resize (it arrives
/// asynchronously), or a short timeout when the size did not change.
Future<void> _settleViewMetrics() async {
  final before = harnessContentSize();
  for (var step = 0; step < _resizePollSteps; step++) {
    await Future<void>.delayed(_resizePollInterval);
    if (harnessContentSize() != before) break;
  }
  await Future<void>.delayed(_resizeSettleDelay);
}

void _preventWindowsActivation(int windowId) {
  final user32 = DynamicLibrary.open('user32.dll');
  final getWindowLong = user32
      .lookupFunction<IntPtr Function(IntPtr, Int32), int Function(int, int)>(
        'GetWindowLongPtrW',
      );
  final setWindowLong = user32
      .lookupFunction<
        IntPtr Function(IntPtr, Int32, IntPtr),
        int Function(int, int, int)
      >('SetWindowLongPtrW');
  const extendedStyleIndex = -20;
  const noActivateStyle = 0x08000000;
  final style = getWindowLong(windowId, extendedStyleIndex);
  setWindowLong(windowId, extendedStyleIndex, style | noActivateStyle);
}
