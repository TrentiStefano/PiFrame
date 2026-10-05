import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'app/desktop_chrome.dart';
import 'ui/precision.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'data/theme/theme_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final nativeWindows =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  if (nativeWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('Pi-Crust');
    await windowManager.setMinimumSize(const Size(680, 480));
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
  }
  runApp(
    ProviderScope(
      overrides: [desktopChromeProvider.overrideWithValue(nativeWindows)],
      child: const PiCrustApp(),
    ),
  );
}

class PiCrustApp extends ConsumerWidget {
  const PiCrustApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(currentThemeDataProvider);

    return MaterialApp.router(
      title: 'Pi-Crust',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: themeData,
      builder: (context, child) =>
          LaunchReveal(child: child ?? const SizedBox.shrink()),
    );
  }
}
