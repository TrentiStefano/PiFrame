import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/window/window_state_service.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  final service = WindowStateService.instance;
  late Directory tempDir;
  late File stateFile;
  late _FakeWindowManager manager;

  setUp(() {
    service.resetForTesting();
    tempDir = Directory.systemTemp.createTempSync('window_restore_test_');
    stateFile = File('${tempDir.path}/window_state.json');
    manager = _FakeWindowManager();
    service.setStorageFileForTesting(stateFile);
    service.setWindowManagerForTesting(manager);
  });

  tearDown(() {
    service.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'normal restore keeps size, ignores saved coordinates, and centers',
    () async {
      await service.saveState(
        const WindowState(width: 1280, height: 800, x: 45, y: 90),
      );

      await service.restoreWindow();

      expect(manager.size, const Size(1280, 800));
      expect(manager.centerCalls, 1);
      expect(manager.positionCalls, 0);
    },
  );

  test('default normal restore centers the default window size', () async {
    await service.restoreWindow();

    expect(manager.size, const Size(1100, 720));
    expect(manager.centerCalls, 1);
  });

  test('maximized and fullscreen states restore after normal size', () async {
    await service.saveState(
      const WindowState(width: 1260, height: 760, isMaximized: true),
    );
    await service.restoreWindow();
    expect(manager.size, const Size(1260, 760));
    expect(manager.maximizeCalls, 1);
    expect(manager.centerCalls, 0);

    await service.saveState(
      const WindowState(width: 1260, height: 760, isFullScreen: true),
    );
    manager = _FakeWindowManager();
    service.setWindowManagerForTesting(manager);
    await service.restoreWindow();
    expect(manager.size, const Size(1260, 760));
    expect(manager.fullScreen, isTrue);
    expect(manager.centerCalls, 0);
  });

  test('maximized dimensions do not replace saved normal bounds', () async {
    const normal = WindowState(width: 1200, height: 740, x: 30, y: 50);
    await service.saveState(normal);
    manager
      ..maximized = true
      ..size = const Size(2400, 1600)
      ..position = const Offset(-1000, -1000);

    await service.recordCurrentWindowState();

    expect(service.currentState.width, 1200);
    expect(service.currentState.height, 740);
    expect(service.currentState.x, 30);
    expect(service.currentState.y, 50);
    expect(service.currentState.isMaximized, isTrue);
  });

  test(
    'minimizing preserves the last maximized state and normal bounds',
    () async {
      const previous = WindowState(
        width: 1200,
        height: 740,
        x: 30,
        y: 50,
        isMaximized: true,
      );
      await service.saveState(previous);
      manager
        ..minimized = true
        ..size = const Size(300, 200)
        ..position = const Offset(-32000, -32000);

      await service.recordCurrentWindowState();

      expect(service.currentState.width, 1200);
      expect(service.currentState.height, 740);
      expect(service.currentState.isMaximized, isTrue);
      final stored = jsonDecode(await stateFile.readAsString()) as Map;
      expect(stored['isMaximized'], isTrue);
      expect(stored['width'], 1200);
    },
  );

  test('awaited state recording persists final normal bounds', () async {
    manager
      ..size = const Size(1180, 760)
      ..position = const Offset(70, 40);

    await service.recordCurrentWindowState();

    final stored = jsonDecode(await stateFile.readAsString()) as Map;
    expect(stored['width'], 1180);
    expect(stored['height'], 760);
    expect(stored['x'], 70);
    expect(stored['y'], 40);
  });
}

class _FakeWindowManager implements WindowManager {
  Size size = const Size(1100, 720);
  Offset position = Offset.zero;
  bool minimized = false;
  bool maximized = false;
  bool fullScreen = false;
  int centerCalls = 0;
  int maximizeCalls = 0;
  int positionCalls = 0;

  @override
  Future<bool> isMinimized() async => minimized;

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<Size> getSize() async => size;

  @override
  Future<Offset> getPosition() async => position;

  @override
  Future<void> setSize(Size value, {bool animate = false}) async =>
      size = value;

  @override
  Future<void> setPosition(Offset value, {bool animate = false}) async {
    positionCalls++;
    position = value;
  }

  @override
  Future<void> center({bool animate = false}) async => centerCalls++;

  @override
  Future<void> maximize({bool vertically = false}) async {
    maximizeCalls++;
    maximized = true;
  }

  @override
  Future<void> setFullScreen(bool value) async => fullScreen = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
