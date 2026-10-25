import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'app/desktop_chrome.dart';
import 'ui/precision.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'data/theme/theme_providers.dart';
import 'data/notifications/desktop_notification_service.dart';
import 'data/window/window_state_service.dart';
import 'ui/startup_assemble_animation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final nativeWindows =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  final desktopWindowLifecycle = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);
  if (desktopWindowLifecycle) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('PiFrame');
    await windowManager.setMinimumSize(const Size(680, 480));
    if (nativeWindows) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
    }
    await DesktopNotificationService.instance.initialize();
    await WindowStateService.instance.restoreWindow();
  }
  runApp(
    ProviderScope(
      overrides: [
        desktopChromeProvider.overrideWithValue(nativeWindows),
        desktopWindowLifecycleProvider.overrideWithValue(desktopWindowLifecycle),
      ],
      child: const PiFrameApp(),
    ),
  );
}

class PiFrameApp extends ConsumerWidget {
  const PiFrameApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(currentThemeDataProvider);

    return MaterialApp.router(
      title: 'PiFrame',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: themeData,
      builder: (context, child) => LaunchReveal(
        child: StartupAssembleOverlay(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
