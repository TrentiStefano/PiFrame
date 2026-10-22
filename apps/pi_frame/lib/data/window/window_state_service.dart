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

  @visibleForTesting
  void setStorageFileForTesting(File? file) {
    _customStorageFile = file;
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
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final isFull = await windowManager.isFullScreen();
      final isMax = await windowManager.isMaximized();
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();

      final state = WindowState(
        width: size.width,
        height: size.height,
        x: pos.dx,
        y: pos.dy,
        isFullScreen: isFull,
        isMaximized: isMax,
      );
      await saveState(state);
    } catch (_) {}
  }

  Future<void> restoreWindow() async {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final state = await loadState();
      if (state.isFullScreen) {
        await windowManager.setFullScreen(true);
      } else if (state.isMaximized) {
        await windowManager.maximize();
      } else {
        final width = state.width.clamp(680.0, 4000.0);
        final height = state.height.clamp(480.0, 3000.0);
        await windowManager.setSize(Size(width, height));
        if (state.x != null && state.y != null) {
          await windowManager.setPosition(Offset(state.x!, state.y!));
        }
      }
    } catch (_) {}
  }
}
