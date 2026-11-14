import 'package:flutter/material.dart';

import 'app/harness_mode.dart';
import 'harness/harness_extensions.dart';
import 'harness/harness_window.dart';
import 'main.dart' show runPiFrame;

const _harnessSize = String.fromEnvironment(
  'PIFRAME_HARNESS_SIZE',
  defaultValue: '1280x800',
);

final _rootBoundaryKey = GlobalKey();

Future<void> main() {
  enableHarnessMode();
  return runPiFrame(
    configureWindow: () =>
        configureHarnessWindow(_parseHarnessSize(_harnessSize)),
    rootWrapper: (child) =>
        RepaintBoundary(key: _rootBoundaryKey, child: child),
  ).then((_) => registerHarnessExtensions(_rootBoundaryKey));
}

Size _parseHarnessSize(String value) {
  final parts = value.toLowerCase().split('x');
  if (parts.length != 2) return const Size(1280, 800);
  final width = double.tryParse(parts[0]);
  final height = double.tryParse(parts[1]);
  if (width == null || height == null || width <= 0 || height <= 0) {
    return const Size(1280, 800);
  }
  return Size(width, height);
}
