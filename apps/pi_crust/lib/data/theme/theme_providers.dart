import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import 'theme_storage.dart';

export 'theme_storage.dart';

final themeStorageProvider = Provider<ThemeStorage>((ref) {
  return FileThemeStorage();
});

final themeRepositoryProvider = Provider<ThemeRepository>((ref) {
  final storage = ref.watch(themeStorageProvider);
  final savedThemeId = storage.loadActiveThemeIdSync();

  final repo = ThemeRepository();
  final initialTheme = savedThemeId ?? 'crust-dark';
  if (repo.hasTheme(initialTheme)) {
    repo.setActiveTheme(initialTheme);
  }

  // Load bundled asset themes & user themes
  Future.microtask(() async {
    final assetThemes = [
      'assets/themes/crust-dark.json',
      'assets/themes/crust-light.json',
    ];
    for (final path in assetThemes) {
      try {
        final content = await rootBundle.loadString(path);
        repo.registerThemeJson(content);
      } catch (_) {}
    }

    // Attempt to watch and load user ~/.pi-crust/themes/
    try {
      final userThemesDir = storage.resolveUserThemesDir();
      if (userThemesDir != null && userThemesDir.existsSync()) {
        final files = userThemesDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'));
        for (final file in files) {
          try {
            final content = file.readAsStringSync();
            repo.registerThemeJson(content);
          } catch (_) {}
        }
        repo.watchDirectory(userThemesDir);
      }
    } catch (_) {}

    // Ensure the saved theme or intended theme is activated once all themes are loaded
    final activeToRestore = storage.loadActiveThemeIdSync() ?? initialTheme;
    if (repo.hasTheme(activeToRestore)) {
      repo.setActiveTheme(activeToRestore);
    }
  });

  ref.onDispose(() => repo.dispose());
  return repo;
});

class ThemeNotifier extends StateNotifier<ThemeSpec> {
  final ThemeRepository _repo;
  final ThemeStorage _storage;
  late final StreamSubscription<List<ThemeSpec>> _subscription;

  ThemeNotifier(this._repo, this._storage) : super(_repo.activeTheme) {
    _subscription = _repo.watch().listen((_) {
      state = _repo.activeTheme;
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  void setTheme(String themeId) {
    _repo.setActiveTheme(themeId);
    state = _repo.activeTheme;
    _storage.saveActiveThemeId(themeId);
  }

  Future<ThemeSpec> importThemeFromJson(String jsonContent) async {
    final spec = VsCodeThemeConverter.parseAnyThemeJson(jsonContent);
    final filename = '${spec.id}.json';
    await _storage.saveUserThemeFile(filename, jsonContent);
    _repo.registerTheme(spec);
    setTheme(spec.id);
    return spec;
  }
}

final activeThemeSpecProvider = StateNotifierProvider<ThemeNotifier, ThemeSpec>(
  (ref) {
    final repo = ref.watch(themeRepositoryProvider);
    final storage = ref.watch(themeStorageProvider);
    return ThemeNotifier(repo, storage);
  },
);

final currentThemeDataProvider = Provider<ThemeData>((ref) {
  final spec = ref.watch(activeThemeSpecProvider);
  return spec.toThemeData();
});
