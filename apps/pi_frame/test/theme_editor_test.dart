import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/theme/theme_providers.dart';
import 'package:pi_frame/features/settings/theme_editor_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _MemoryThemeStorage extends ThemeStorage {
  final Map<String, String> userThemes = {};
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
  Future<File?> saveUserThemeFile(String filename, String content) async {
    userThemes[filename] = content;
    return null;
  }
}

void main() {
  group('ThemeSpec mutation & serialization', () {
    test('copyWith and toJson work accurately', () {
      final base = ThemeSpec(
        schemaVersion: 1,
        id: 'test-theme',
        name: 'Test Theme',
        author: 'Tester',
        version: '1.0.0',
        variant: 'dark',
        rawColors: {'background': '#111111', 'accent': '#FF0055'},
        rawSyntax: {'keyword': '#FFAA00'},
      );

      final copy = base.copyWith(
        name: 'Custom Test Theme',
        variant: 'light',
        rawColors: {'background': '#FFFFFF', 'accent': '#0055FF'},
      );

      expect(copy.id, 'test-theme');
      expect(copy.name, 'Custom Test Theme');
      expect(copy.variant, 'light');
      expect(copy.rawColors['background'], '#FFFFFF');

      final json = copy.toJson();
      expect(json['schemaVersion'], 1);
      expect(json['name'], 'Custom Test Theme');
      expect(json['variant'], 'light');
      expect(json['colors']['background'], '#FFFFFF');
      expect(json['colors']['accent'], '#0055FF');
      expect(json['syntax']['keyword'], '#FFAA00');
    });
  });

  testWidgets('ThemeEditorDialog customization and save workflow', (
    tester,
  ) async {
    final repository = ThemeRepository();
    addTearDown(repository.dispose);
    for (final flavor in ['light', 'dark']) {
      final file = File('assets/themes/piframe-$flavor.json');
      if (file.existsSync()) {
        repository.registerThemeJson(file.readAsStringSync());
      }
    }
    if (repository.availableThemes.isNotEmpty) {
      repository.setActiveTheme(repository.availableThemes.first.id);
    }

    final storage = _MemoryThemeStorage();
    final langNotifier = AppLanguageNotifier()..setLanguage(AppLanguage.it);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          themeRepositoryProvider.overrideWithValue(repository),
          themeStorageProvider.overrideWithValue(storage),
          appLanguageProvider.overrideWith((ref) => langNotifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => ThemeEditorDialog.show(context),
                    child: const Text('Open Editor'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Theme Editor Dialog
    await tester.tap(find.text('Open Editor'));
    await tester.pumpAndSettle();

    // Verify dialog header, inputs, and previews
    expect(find.text('Editor Temi Personalizzati'), findsOneWidget);
    expect(find.text('Anteprima Componenti'), findsOneWidget);
    expect(find.text('Scheda Bento & Superfici'), findsOneWidget);
    expect(find.text('Pulsante Accento'), findsOneWidget);
    expect(find.text('Scuro (Dark)'), findsWidgets);

    // Edit Theme Name
    final nameInput = find.byType(TextField).first;
    await tester.enterText(nameInput, 'Mio Tema Pro');
    await tester.pumpAndSettle();

    // Tap on a color row to customize
    final bgRow = find.byKey(const ValueKey('theme-editor-color-background'));
    expect(bgRow, findsOneWidget);
    await tester.tap(bgRow);
    await tester.pumpAndSettle();

    // Color picker dialog should appear
    expect(find.text('Sfondo Principale'), findsWidgets);
    expect(find.text('Applica'), findsOneWidget);
    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();

    // Tap "Salva e Applica Tema"
    final saveBtn = find.text('Salva e Applica Tema');
    expect(saveBtn, findsOneWidget);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // Verify dialog closed
    expect(find.text('Editor Temi Personalizzati'), findsNothing);

    // Verify custom theme was saved to storage
    expect(storage.userThemes.containsKey('custom-mio-tema-pro.json'), isTrue);
    expect(storage.userThemes['custom-mio-tema-pro.json'], contains('Mio Tema Pro'));

    // Verify theme was registered and set as active in repository
    expect(repository.hasTheme('custom-mio-tema-pro'), isTrue);
    expect(repository.activeThemeId, 'custom-mio-tema-pro');
  });
}
