import 'package:flutter/material.dart';

import 'app/harness_mode.dart';
import 'harness/harness_extensions.dart';
import 'harness/harness_window.dart';
import 'main.dart' show runPiFrame;

const _harnessSize = String.fromEnvironment('PIFRAME_HARNESS_SIZE', defaultValue: '1920x1032');

final _rootBoundaryKey = GlobalKey();

Future<void> main() async {
  enableHarnessMode();
  final size = _parseHarnessSize(_harnessSize);
  await runPiFrame(
    configureWindow: () => configureHarnessWindow(size),
    rootWrapper: (child) => RepaintBoundary(key: _rootBoundaryKey, child: child),
  );
  registerHarnessExtensions(_rootBoundaryKey);
  // --size is the app's drawing area: grow the window by its frame.
  await setHarnessContentSize(size);
}

Size _parseHarnessSize(String value) {
  final parts = value.toLowerCase().split('x');
  if (parts.length != 2) return const Size(1920, 1032);
  final width = double.tryParse(parts[0]);
  final height = double.tryParse(parts[1]);
  if (width == null || height == null || width <= 0 || height <= 0) {
    return const Size(1920, 1032);
  }
  return Size(width, height);
}
