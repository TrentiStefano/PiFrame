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
      expect(strings.tabAgents, 'AGENTI');
      expect(strings.agentsTitle, 'Configurazione agenti e sottoagenti');
      expect(strings.agentsPackagesLabel, 'Pacchetti:');
      expect(strings.agentsContextSingleTierTooltip, 'Il modello ha un solo livello di contesto');
      expect(strings.agentsModelUnavailableWarning, 'Non disponibile con le credenziali attuali');
      expect(strings.agentsNotAvailableShort, 'n/d');
      expect(strings.languageSectionTitle, "Lingua dell'Applicazione");
      expect(strings.openThemeEditorBtn, 'Editor temi / Personalizza tema');
      expect(strings.updateNoticeTitle, 'Aggiornamenti rilevati');
      expect(strings.branchChipTooltip, 'Cambia ramo Git');
      expect(strings.branchPickerTitle, 'Passa a un altro ramo');
      expect(strings.workspaceDirtyDialogTitle, 'Modifiche non salvate');
      expect(
        strings.workspaceDirtyDialogMessage(2, 1),
        'Hai 2 file modificati e 1 non tracciati. Il cambio di ramo è bloccato per proteggere le tue modifiche.',
      );
      expect(strings.stashAndSwitchBtn, 'Salva nello stash e cambia');
      expect(strings.branchSwitched('feature'), 'Passato al ramo feature');
      expect(
        strings.branchSwitchedStashNotice('stash-1'),
        'Le tue modifiche sono state salvate nello stash: stash-1',
      );
      expect(strings.branchSwitchFailedTitle, 'Cambio di ramo non riuscito');
      expect(
        strings.stashRetainedSafeNotice('stash-1'),
        'Le tue modifiche sono al sicuro nello stash: stash-1',
      );
      expect(
        strings.branchSwitchAgentWorking,
        'Impossibile cambiare ramo mentre l\'agente sta lavorando',
      );
      expect(strings.branchNotFound, 'Ramo non trovato');
      expect(strings.branchInvalidName, 'Nome del ramo non valido');
      expect(strings.updateAllPackages, 'Aggiorna tutto');
      expect(
        strings.updateAllPackagesMessage(2),
        contains('2 pacchetti utente con aggiornamenti disponibili'),
      );
      expect(
        strings.packageUpdateSummary(1, 2, 3),
        contains('Già aggiornati: 2.'),
      );
      expect(
        strings.packageUpdateUnavailable('1.2.0', 'Windows'),
        contains('non compatibile'),
      );
      expect(strings.packageUpdateNotVerified, contains('Riavvia il daemon'));
    });

    test('AppStrings provides correct English translations', () {
      const strings = AppStrings(AppLanguage.en);
      expect(strings.isItalian, isFalse);
      expect(strings.settingsTitle, 'PiFrame Settings');
      expect(strings.tabPackages, 'PACKAGES');
      expect(strings.tabAppearance, 'APPEARANCE');
      expect(strings.tabAgents, 'AGENTS');
      expect(strings.agentsTitle, 'Agent & Subagent Configuration');
      expect(strings.agentsPackagesLabel, 'Packages:');
      expect(strings.agentsContextSingleTierTooltip, 'Model has a single context tier');
      expect(strings.agentsModelUnavailableWarning, 'Not available with current credentials');
      expect(strings.agentsNotAvailableShort, 'N/A');
      expect(strings.languageSectionTitle, 'Application Language');
      expect(strings.openThemeEditorBtn, 'Theme Editor / Customize Theme');
      expect(strings.updateNoticeTitle, 'Updates Available');
      expect(strings.branchChipTooltip, 'Switch Git branch');
      expect(strings.branchPickerTitle, 'Switch branch');
      expect(strings.workspaceDirtyDialogTitle, 'Uncommitted Changes');
      expect(
        strings.workspaceDirtyDialogMessage(2, 1),
        'You have 2 modified and 1 untracked files. Switching branch is blocked to protect your changes.',
      );
      expect(strings.stashAndSwitchBtn, 'Stash changes and switch');
      expect(strings.branchSwitched('feature'), 'Switched to feature');
      expect(
        strings.branchSwitchedStashNotice('stash-1'),
        'Your changes were stashed: stash-1',
      );
      expect(strings.branchSwitchFailedTitle, 'Branch switch failed');
      expect(
        strings.stashRetainedSafeNotice('stash-1'),
        'Your changes are safe in the stash: stash-1',
      );
      expect(
        strings.branchSwitchAgentWorking,
        'Cannot switch branch while the agent is working',
      );
      expect(strings.branchNotFound, 'Branch not found');
      expect(strings.branchInvalidName, 'Invalid branch name');
      expect(strings.updateAllPackages, 'Update all');
      expect(
        strings.updateAllPackagesMessage(2),
        contains('2 user packages with available updates'),
      );
      expect(
        strings.packageUpdateSummary(1, 2, 3),
        contains('Already up to date: 2.'),
      );
      expect(
        strings.packageUpdateUnavailable('1.2.0', 'Windows'),
        contains('not compatible'),
      );
      expect(
        strings.packageUpdateNotVerified,
        contains('Restart the updated daemon'),
      );
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
