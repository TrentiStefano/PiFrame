import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

class WindowState {
  final double width;
  final double height;
  final double? x;
  final double? y;
  final bool isFullScreen;
  final bool isMaximized;

  const WindowState({
    this.width = 1100,
    this.height = 720,
    this.x,
    this.y,
    this.isFullScreen = false,
    this.isMaximized = false,
  });

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'x': x,
    'y': y,
    'isFullScreen': isFullScreen,
    'isMaximized': isMaximized,
  };

  factory WindowState.fromJson(Map<String, dynamic> json) => WindowState(
    width: (json['width'] as num?)?.toDouble() ?? 1100,
    height: (json['height'] as num?)?.toDouble() ?? 720,
    x: (json['x'] as num?)?.toDouble(),
    y: (json['y'] as num?)?.toDouble(),
    isFullScreen: json['isFullScreen'] as bool? ?? false,
    isMaximized: json['isMaximized'] as bool? ?? false,
  );
}

class WindowStateService {
  WindowStateService._();
  static final WindowStateService instance = WindowStateService._();

  WindowState _currentState = const WindowState();
  WindowState get currentState => _currentState;

  Timer? _saveDebounceTimer;
  File? _customStorageFile;
  WindowManager? _windowManagerForTesting;

  WindowManager get _windowManager => _windowManagerForTesting ?? windowManager;
  bool get _canUseWindowManager =>
      !kIsWeb &&
      (!Platform.environment.containsKey('FLUTTER_TEST') ||
          _windowManagerForTesting != null);

  @visibleForTesting
  void setStorageFileForTesting(File? file) {
    _customStorageFile = file;
  }

  @visibleForTesting
  void setWindowManagerForTesting(WindowManager? manager) {
    _windowManagerForTesting = manager;
  }

  @visibleForTesting
  void resetForTesting() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _customStorageFile = null;
    _windowManagerForTesting = null;
    _currentState = const WindowState();
  }

  File? _getStorageFile() {
    if (_customStorageFile != null) return _customStorageFile;
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.piframe');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}/window_state.json');
    } catch (_) {
      return null;
    }
  }

  Future<WindowState> loadState() async {
    final file = _getStorageFile();
    if (file != null && file.existsSync()) {
      try {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        _currentState = WindowState.fromJson(map);
        return _currentState;
      } catch (_) {}
    }
    return _currentState;
  }

  Future<void> saveState(WindowState state) async {
    _currentState = state;
    final file = _getStorageFile();
    if (file != null) {
      try {
        await file.writeAsString(jsonEncode(state.toJson()));
      } catch (_) {}
    }
  }

  void debounceRecordCurrentState() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      recordCurrentWindowState();
    });
  }

  Future<void> recordCurrentWindowState() async {
    if (!_canUseWindowManager) return;
    try {
      final manager = _windowManager;
      if (await manager.isMinimized()) {
        await saveState(_currentState);
        return;
      }
      final isFull = await manager.isFullScreen();
      final isMax = await manager.isMaximized();
      final geometry = isFull || isMax ? _currentState : null;
      final size = geometry == null ? await manager.getSize() : null;
      final pos = geometry == null ? await manager.getPosition() : null;

      await saveState(
        WindowState(
          width: geometry?.width ?? size!.width,
          height: geometry?.height ?? size!.height,
          x: geometry == null ? pos!.dx : geometry.x,
          y: geometry == null ? pos!.dy : geometry.y,
          isFullScreen: isFull,
          isMaximized: isMax,
        ),
      );
    } catch (_) {}
  }

  Future<void> restoreWindow() async {
    if (!_canUseWindowManager) return;
    try {
      final manager = _windowManager;
      final state = await loadState();
      final width = state.width.clamp(680.0, 4000.0);
      final height = state.height.clamp(480.0, 3000.0);
      await manager.setSize(Size(width, height));
      if (state.isFullScreen) {
        await manager.setFullScreen(true);
      } else if (state.isMaximized) {
        await manager.maximize();
      } else {
        await manager.center();
      }
    } catch (_) {}
  }
}
