import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// The desktop window the app runs in: caption buttons, close handling.
abstract class WindowService {
  Future<void> minimize();

  Future<void> maximize();

  Future<void> unmaximize();

  Future<bool> isMaximized();

  Future<void> close();

  /// When true, the window asks the app before closing instead of closing.
  Future<void> setPreventClose(bool prevent);
}

class WindowManagerService implements WindowService {
  const WindowManagerService();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> unmaximize() => windowManager.unmaximize();

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<void> setPreventClose(bool prevent) => windowManager.setPreventClose(prevent);
}

final windowServiceProvider = Provider<WindowService>((ref) => const WindowManagerService());
