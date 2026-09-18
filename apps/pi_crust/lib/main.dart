import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'data/theme/theme_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: PiCrustApp()));
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
    );
  }
}
