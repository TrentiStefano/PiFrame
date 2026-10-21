import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'theme_storage.dart';

export 'theme_storage.dart';

final themeStorageProvider = Provider<ThemeStorage>((ref) {
  return FileThemeStorage();
});

final themeRepositoryProvider = Provider<ThemeRepository>((ref) {
  final storage = ref.watch(themeStorageProvider);
  final savedSettings = storage.loadSettingsSync();

  final repo = ThemeRepository();
  final brightness = PlatformDispatcher.instance.platformBrightness;
  final initialTheme = savedSettings.useSystemTheme
      ? (brightness == Brightness.dark
          ? savedSettings.defaultDarkThemeId
          : savedSettings.defaultLightThemeId)
      : savedSettings.activeThemeId;

  if (repo.hasTheme(initialTheme)) {
    repo.setActiveTheme(initialTheme);
  }

  // Load bundled asset themes & user themes
  Future.microtask(() async {
    final assetThemes = [
      'assets/themes/piframe-dark.json',
      'assets/themes/piframe-light.json',
    ];
    for (final path in assetThemes) {
      try {
        final content = await rootBundle.loadString(path);
        repo.registerThemeJson(content);
      } catch (_) {}
    }

    // Attempt to watch and load user ~/.piframe/themes/
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
    final settingsToRestore = storage.loadSettingsSync();
    final currentBrightness = PlatformDispatcher.instance.platformBrightness;
    final activeToRestore = settingsToRestore.useSystemTheme
        ? (currentBrightness == Brightness.dark
            ? settingsToRestore.defaultDarkThemeId
            : settingsToRestore.defaultLightThemeId)
        : settingsToRestore.activeThemeId;

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
  ThemeSettings _settings;
  late final StreamSubscription<List<ThemeSpec>> _subscription;

  ThemeNotifier(this._repo, this._storage)
      : _settings = _storage.loadSettingsSync(),
        super(_repo.activeTheme) {
    _subscription = _repo.watch().listen((_) {
      if (state.id != _repo.activeTheme.id) {
        state = _repo.activeTheme;
      }
    });

    _applyResolvedTheme();
  }

  ThemeSettings get settings => _settings;

  void _applyResolvedTheme() {
    final targetId = _resolveCurrentThemeId();
    if (_repo.activeThemeId != targetId && _repo.hasTheme(targetId)) {
      _repo.setActiveTheme(targetId);
    }
    if (state.id != _repo.activeTheme.id) {
      state = _repo.activeTheme;
    }
  }

  String _resolveCurrentThemeId() {
    if (!_settings.useSystemTheme) {
      return _settings.activeThemeId;
    }
    final brightness = PlatformDispatcher.instance.platformBrightness;
    return brightness == Brightness.dark
        ? _settings.defaultDarkThemeId
        : _settings.defaultLightThemeId;
  }

  void onPlatformBrightnessChanged(Brightness brightness) {
    if (_settings.useSystemTheme) {
      final targetId = brightness == Brightness.dark
          ? _settings.defaultDarkThemeId
          : _settings.defaultLightThemeId;
      if (_repo.activeThemeId != targetId && _repo.hasTheme(targetId)) {
        _repo.setActiveTheme(targetId);
      }
      if (state.id != _repo.activeTheme.id) {
        state = _repo.activeTheme;
      }
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  void setTheme(String themeId) {
    _settings = _settings.copyWith(activeThemeId: themeId);
    _storage.saveSettings(_settings);
    if (_repo.activeThemeId != themeId && _repo.hasTheme(themeId)) {
      _repo.setActiveTheme(themeId);
    }
    if (state.id != _repo.activeTheme.id) {
      state = _repo.activeTheme;
    }
  }

  void setUseSystemTheme(bool useSystem) {
    _settings = _settings.copyWith(useSystemTheme: useSystem);
    _storage.saveSettings(_settings);
    _applyResolvedTheme();
  }

  void setDefaultDarkTheme(String themeId) {
    _settings = _settings.copyWith(defaultDarkThemeId: themeId);
    _storage.saveSettings(_settings);
    _applyResolvedTheme();
  }

  void setDefaultLightTheme(String themeId) {
    _settings = _settings.copyWith(defaultLightThemeId: themeId);
    _storage.saveSettings(_settings);
    _applyResolvedTheme();
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

class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  final ThemeStorage _storage;
  final ThemeNotifier _themeNotifier;

  ThemeSettingsNotifier(this._storage, this._themeNotifier)
      : super(_storage.loadSettingsSync());

  void setUseSystemTheme(bool useSystem) {
    state = state.copyWith(useSystemTheme: useSystem);
    _storage.saveSettings(state);
    _themeNotifier.setUseSystemTheme(useSystem);
  }

  void setDefaultDarkTheme(String themeId) {
    state = state.copyWith(defaultDarkThemeId: themeId);
    _storage.saveSettings(state);
    _themeNotifier.setDefaultDarkTheme(themeId);
  }

  void setDefaultLightTheme(String themeId) {
    state = state.copyWith(defaultLightThemeId: themeId);
    _storage.saveSettings(state);
    _themeNotifier.setDefaultLightTheme(themeId);
  }
}

final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>((ref) {
  final storage = ref.watch(themeStorageProvider);
  final themeNotifier = ref.watch(activeThemeSpecProvider.notifier);
  return ThemeSettingsNotifier(storage, themeNotifier);
});

final currentThemeDataProvider = Provider<ThemeData>((ref) {
  final spec = ref.watch(activeThemeSpecProvider);
  return spec.toThemeData();
});

