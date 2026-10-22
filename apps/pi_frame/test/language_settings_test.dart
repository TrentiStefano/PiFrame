import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/theme/theme_providers.dart';
import 'package:pi_frame/features/settings/settings_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  group('AppLanguage and AppStrings', () {
    test('AppLanguage.fromCode parses properly with fallback to it', () {
      expect(AppLanguage.fromCode('it'), AppLanguage.it);
      expect(AppLanguage.fromCode('IT'), AppLanguage.it);
      expect(AppLanguage.fromCode('en'), AppLanguage.en);
      expect(AppLanguage.fromCode('EN'), AppLanguage.en);
      expect(AppLanguage.fromCode(null), AppLanguage.it);
      expect(AppLanguage.fromCode('fr'), AppLanguage.it);
    });

    test('AppStrings provides correct Italian translations', () {
      const strings = AppStrings(AppLanguage.it);
      expect(strings.isItalian, isTrue);
      expect(strings.settingsTitle, 'Impostazioni PiFrame');
      expect(strings.tabPackages, 'PACCHETTI');
      expect(strings.tabAppearance, 'ASPETTO');
      expect(strings.languageSectionTitle, "Lingua dell'Applicazione");
      expect(strings.openThemeEditorBtn, 'Editor Temi / Personalizza Tema');
      expect(strings.updateNoticeTitle, 'Aggiornamenti Rilevati');
    });

    test('AppStrings provides correct English translations', () {
      const strings = AppStrings(AppLanguage.en);
      expect(strings.isItalian, isFalse);
      expect(strings.settingsTitle, 'PiFrame Settings');
      expect(strings.tabPackages, 'PACKAGES');
      expect(strings.tabAppearance, 'APPEARANCE');
      expect(strings.languageSectionTitle, 'Application Language');
      expect(strings.openThemeEditorBtn, 'Theme Editor / Customize Theme');
      expect(strings.updateNoticeTitle, 'Updates Available');
    });

    test('AppLanguageNotifier updates state', () {
      final notifier = AppLanguageNotifier();
      expect(notifier.state, AppLanguage.it);

      notifier.setLanguage(AppLanguage.en);
      expect(notifier.state, AppLanguage.en);

      notifier.setLanguage(AppLanguage.it);
      expect(notifier.state, AppLanguage.it);
    });
  });

  testWidgets('SettingsView appearance tab allows switching language', (
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

    final languageNotifier = AppLanguageNotifier();
    languageNotifier.setLanguage(AppLanguage.it);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          themeRepositoryProvider.overrideWithValue(repository),
          appLanguageProvider.overrideWith((ref) => languageNotifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: Scaffold(
            body: SettingsView(
              initialTabIndex: 3, // Tab 4: Aspetto
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial Italian texts
    expect(find.text('Impostazioni PiFrame'), findsOneWidget);
    expect(find.text('PACCHETTI'), findsOneWidget);
    expect(find.text('ASPETTO'), findsOneWidget);
    expect(find.text("Lingua dell'Applicazione"), findsOneWidget);

    // Find and tap the language dropdown
    final dropdownFinder = find.byKey(
      const ValueKey('settings-language-dropdown'),
    );
    expect(dropdownFinder, findsOneWidget);
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();

    // Select English (EN)
    final englishOption = find.text('English (EN)').last;
    await tester.tap(englishOption);
    await tester.pumpAndSettle();

    // Verify that the UI switched to English
    expect(find.text('PiFrame Settings'), findsOneWidget);
    expect(find.text('PACKAGES'), findsOneWidget);
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('Application Language'), findsOneWidget);
  });
}
