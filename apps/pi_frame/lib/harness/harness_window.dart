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
