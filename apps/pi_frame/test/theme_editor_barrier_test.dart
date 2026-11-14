import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/theme/theme_providers.dart';
import 'package:pi_frame/features/settings/theme_editor_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _MemoryThemeStorage extends ThemeStorage {
  ThemeSettings settings = const ThemeSettings();

  @override
  Directory? resolveUserThemesDir() => null;

  @override
  ThemeSettings loadSettingsSync() => settings;

  @override
  Future<ThemeSettings> loadSettings() async => settings;

  @override
  String? loadActiveThemeIdSync() => settings.activeThemeId;

  @override
  Future<String?> loadActiveThemeId() async => settings.activeThemeId;

  @override
  Future<void> saveSettings(ThemeSettings newSettings) async {
    settings = newSettings;
  }

  @override
  Future<void> saveActiveThemeId(String themeId) async {
    settings = settings.copyWith(activeThemeId: themeId);
  }

  @override
  Future<File?> saveUserThemeFile(String filename, String content) async =>
      null;
}

void main() {
  testWidgets('theme editor opens through the frame dialog route and ignores barrier taps', (
    tester,
  ) async {
    final repository = ThemeRepository();
    addTearDown(repository.dispose);
    final langNotifier = AppLanguageNotifier()..setLanguage(AppLanguage.en);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          themeRepositoryProvider.overrideWithValue(repository),
          themeStorageProvider.overrideWithValue(_MemoryThemeStorage()),
          appLanguageProvider.overrideWith((ref) => langNotifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open-theme-editor'),
                  onPressed: () => ThemeEditorDialog.show(context),
                  child: const Text('Open Editor'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-theme-editor')));
    await tester.pumpAndSettle();
    expect(find.byType(ThemeEditorDialog), findsOneWidget);

    // A tap on the barrier must not dismiss the editor (barrierDismissible: false).
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(ThemeEditorDialog), findsOneWidget);
  });
}
