@Timeout(Duration(seconds: 30))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/theme/theme_providers.dart';
import 'package:pi_frame/features/settings/settings_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  group('Theme persistence and VSCode theme importing', () {
    test('themeRepositoryProvider initializes with piframe-dark or saved theme instead of forcing light mode', () {
      final storage = MemoryThemeStorage(); // No saved theme initially
      final container = ProviderContainer(
        overrides: [
          themeStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(themeRepositoryProvider);
      // Must not default to piframe-light! Default should be piframe-dark
      expect(repo.activeThemeId, 'piframe-dark');
      expect(repo.activeTheme.variant, 'dark');
    });

    test('themeRepositoryProvider restores saved theme from storage on startup', () {
      final storage = MemoryThemeStorage('piframe-light');
      final container = ProviderContainer(
        overrides: [
          themeStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(themeRepositoryProvider);
      expect(repo.activeThemeId, 'piframe-light');
    });

    test('setTheme persists chosen theme ID to storage', () {
      final storage = MemoryThemeStorage('piframe-dark');
      final container = ProviderContainer(
        overrides: [
          themeStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(activeThemeSpecProvider.notifier);
      notifier.setTheme('piframe-light');

      expect(container.read(activeThemeSpecProvider).id, 'piframe-light');
      expect(storage.loadActiveThemeIdSync(), 'piframe-light');

      notifier.setTheme('piframe-dark');
      expect(container.read(activeThemeSpecProvider).id, 'piframe-dark');
      expect(storage.loadActiveThemeIdSync(), 'piframe-dark');
    });

    test('importThemeFromJson converts VSCode JSON, saves user theme file, and activates it', () async {
      final storage = MemoryThemeStorage('piframe-dark');
      final container = ProviderContainer(
        overrides: [
          themeStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      const vscodeThemeJson = '''
      // VSCode Monokai Sample
      {
        "name": "Monokai Pro Test",
        "type": "dark",
        "colors": {
          "editor.background": "#2d2a2e",
          "editor.foreground": "#fcfcfa",
          "activityBar.background": "#19181a",
          "focusBorder": "#ffd866"
        },
        "tokenColors": [
          {
            "scope": "keyword",
            "settings": {
              "foreground": "#ff6188"
            }
          }
        ]
      }
      ''';

      final notifier = container.read(activeThemeSpecProvider.notifier);
      final importedSpec = await notifier.importThemeFromJson(vscodeThemeJson);

      expect(importedSpec.name, 'Monokai Pro Test');
      expect(importedSpec.id, 'vscode-monokai-pro-test');
      expect(importedSpec.variant, 'dark');

      // Check that it was saved to storage
      expect(storage.userThemes.containsKey('vscode-monokai-pro-test.json'), isTrue);

      // Check that it is now the active theme in provider and persisted
      expect(container.read(activeThemeSpecProvider).id, 'vscode-monokai-pro-test');
      expect(storage.loadActiveThemeIdSync(), 'vscode-monokai-pro-test');

      final tokens = container.read(activeThemeSpecProvider).toTokens();
      expect(tokens.background, const Color(0xFF2D2A2E));
      expect(tokens.textPrimary, const Color(0xFFFCFCFA));
      expect(tokens.accent, const Color(0xFFFFD866));
      expect(tokens.syntaxKeyword, const Color(0xFFFF6188));
    });

    testWidgets('SettingsView displays Import Theme button', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryThemeStorage('piframe-dark');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeStorageProvider.overrideWithValue(storage),
            daemonEndpointProvider.overrideWith((ref) async => null),
            pcpClientProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: Scaffold(
              body: SettingsView(
                onClose: () {},
                initialTabIndex: 3, // Aspetto tab
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final importBtn = find.byKey(const ValueKey('settings-import-theme-btn'));
      expect(importBtn, findsOneWidget);
      expect(find.text('Importa tema JSON (VSCode / PiFrame)'), findsOneWidget);
    });

    test('default dark and light themes persist and update independently', () {
      final storage = MemoryThemeStorage();
      final container = ProviderContainer(
        overrides: [
          themeStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(activeThemeSpecProvider.notifier);
      expect(notifier.settings.defaultDarkThemeId, 'piframe-dark');
      expect(notifier.settings.defaultLightThemeId, 'piframe-light');
      expect(notifier.settings.useSystemTheme, isFalse);

      notifier.setDefaultDarkTheme('catppuccin-mocha');
      expect(notifier.settings.defaultDarkThemeId, 'catppuccin-mocha');
      expect(storage.loadSettingsSync().defaultDarkThemeId, 'catppuccin-mocha');

      notifier.setDefaultLightTheme('solar-light');
      expect(notifier.settings.defaultLightThemeId, 'solar-light');
      expect(storage.loadSettingsSync().defaultLightThemeId, 'solar-light');

      notifier.setUseSystemTheme(true);
      expect(notifier.settings.useSystemTheme, isTrue);
      expect(storage.loadSettingsSync().useSystemTheme, isTrue);
    });

    testWidgets('SettingsView displays system theme switch and default theme dropdowns', (tester) async {
      final storage = MemoryThemeStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeStorageProvider.overrideWithValue(storage),
            daemonEndpointProvider.overrideWith((ref) async => null),
            pcpClientProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: Scaffold(
              body: SettingsView(
                onClose: () {},
                initialTabIndex: 3, // Aspetto tab
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settings-theme-system-switch')), findsOneWidget);
      expect(find.text('Usa tema di sistema'), findsOneWidget);
      expect(find.text('Tema Scuro Predefinito:'), findsOneWidget);
      expect(find.text('Tema Chiaro Predefinito:'), findsOneWidget);

      // Toggle system theme switch
      await tester.tap(find.byKey(const ValueKey('settings-theme-system-switch')));
      await tester.pumpAndSettle();

      expect(storage.loadSettingsSync().useSystemTheme, isTrue);
    });
  });
}

