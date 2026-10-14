import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust/data/theme/theme_providers.dart';
import 'package:pi_crust/features/settings/settings_view.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

void main() {
  group('Theme persistence and VSCode theme importing', () {
    test('themeRepositoryProvider initializes with crust-dark or saved theme instead of forcing light mode', () {
      final storage = MemoryThemeStorage(); // No saved theme initially
      final container = ProviderContainer(
        overrides: [
          themeStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(themeRepositoryProvider);
      // Must not default to crust-light! Default should be crust-dark
      expect(repo.activeThemeId, 'crust-dark');
      expect(repo.activeTheme.variant, 'dark');
    });

    test('themeRepositoryProvider restores saved theme from storage on startup', () {
      final storage = MemoryThemeStorage('crust-light');
      final container = ProviderContainer(
        overrides: [
          themeStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(themeRepositoryProvider);
      expect(repo.activeThemeId, 'crust-light');
    });

    test('setTheme persists chosen theme ID to storage', () {
      final storage = MemoryThemeStorage('crust-dark');
      final container = ProviderContainer(
        overrides: [
          themeStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(activeThemeSpecProvider.notifier);
      notifier.setTheme('crust-light');

      expect(container.read(activeThemeSpecProvider).id, 'crust-light');
      expect(storage.loadActiveThemeIdSync(), 'crust-light');

      notifier.setTheme('crust-dark');
      expect(container.read(activeThemeSpecProvider).id, 'crust-dark');
      expect(storage.loadActiveThemeIdSync(), 'crust-dark');
    });

    test('importThemeFromJson converts VSCode JSON, saves user theme file, and activates it', () async {
      final storage = MemoryThemeStorage('crust-dark');
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
      final storage = MemoryThemeStorage('crust-dark');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeStorageProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [CrustTokens.dark]),
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

      expect(find.byKey(const ValueKey('settings-import-theme-btn')), findsOneWidget);
      expect(find.text('Importa tema JSON (VSCode / Pi-Crust)'), findsOneWidget);
    });
  });
}
