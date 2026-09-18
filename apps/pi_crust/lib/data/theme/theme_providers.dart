import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

final themeRepositoryProvider = Provider<ThemeRepository>((ref) {
  final repo = ThemeRepository();

  // Load bundled asset themes
  Future.microtask(() async {
    final assetThemes = [
      'assets/themes/crust-dark.json',
      'assets/themes/crust-light.json',
      'assets/themes/example-minimal.json',
    ];
    for (final path in assetThemes) {
      try {
        final content = await rootBundle.loadString(path);
        repo.registerThemeJson(content);
      } catch (_) {}
    }

    // Attempt to watch user ~/.pi-crust/themes/
    try {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home != null) {
        final userThemesDir = Directory('$home/.pi-crust/themes');
        if (userThemesDir.existsSync()) {
          repo.watchDirectory(userThemesDir);
        }
      }
    } catch (_) {}
  });

  ref.onDispose(() => repo.dispose());
  return repo;
});

class ThemeNotifier extends StateNotifier<ThemeSpec> {
  final ThemeRepository _repo;

  ThemeNotifier(this._repo) : super(_repo.activeTheme) {
    _repo.watch().listen((_) {
      state = _repo.activeTheme;
    });
  }

  void setTheme(String themeId) {
    _repo.setActiveTheme(themeId);
    state = _repo.activeTheme;
  }
}

final activeThemeSpecProvider =
    StateNotifierProvider<ThemeNotifier, ThemeSpec>((ref) {
  final repo = ref.watch(themeRepositoryProvider);
  return ThemeNotifier(repo);
});

final currentThemeDataProvider = Provider<ThemeData>((ref) {
  final spec = ref.watch(activeThemeSpecProvider);
  return spec.toThemeData();
});
