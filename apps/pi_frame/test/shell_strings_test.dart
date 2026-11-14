import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/desktop_chrome.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/language/strings_shell.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/features/status/agent_status_badge.dart';
import 'package:pi_frame/ui/code/code_block.dart';
import 'package:pi_frame/ui/code/diff_block.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  group('ShellStrings Extension Tests', () {
    test('ShellStrings Italian values match existing app strings exactly', () {
      const strings = AppStrings(AppLanguage.it);
      expect(strings.isItalian, isTrue);

      // Desktop Caption
      expect(strings.captionMinimize, 'Riduci a icona');
      expect(strings.captionRestore, 'Ripristina finestra');
      expect(strings.captionMaximize, 'Massimizza finestra');
      expect(strings.captionClose, 'Chiudi finestra');

      // App Shell
      expect(strings.workspaceTitle, 'Area di lavoro');
      expect(strings.closeWorkspaceTooltip, 'Chiudi workspace');
      expect(strings.openSessionsTooltip, 'Apri sessioni');
      expect(strings.localPi, 'Pi locale');
      expect(strings.disconnected, 'Non connesso');
      expect(strings.commandsButtonLabel, 'Comandi');
      expect(strings.togglePanelsTooltip, 'Mostra o nascondi pannelli');
      expect(strings.darkThemeTooltip, 'Tema scuro');
      expect(strings.lightThemeTooltip, 'Tema chiaro');
      expect(strings.settingsTooltip, 'Impostazioni');
      expect(strings.modelAndSessionActionsTooltip, 'Modello e azioni sessione');
      expect(strings.reconnectingToDaemon, 'Riconnessione al daemon in corso...');
      expect(
        strings.daemonUnreachableNotice,
        'Daemon non raggiungibile. Le sessioni restano gestite da Pi.',
      );
      expect(strings.retryAction, 'Riprova');
      expect(strings.expandPaneTooltip('Chat'), 'Espandi pannello Chat');
      expect(strings.expandSessionsSidebarTooltip, 'Espandi barra sessioni');
      expect(strings.sessionsRailHeader, 'SESSIONI');
      expect(strings.recentSessionsHeader, 'Sessioni recenti');
      expect(strings.noFolderDisplay, 'Nessuna cartella');
      expect(strings.newSessionHeroTitle, 'Nuova\nsessione.');
      expect(
        strings.welcomeDescription,
        'Scegli una conversazione o inizia a lavorare con Pi. Il lavoro continua anche quando chiudi la finestra.',
      );
      expect(strings.creatingSession, 'Creazione...');
      expect(strings.newSessionAction, 'Nuova sessione');
      expect(strings.browseSessionsAction, 'Esplora sessioni');
      expect(strings.searchCommandsAction, 'Cerca nei comandi');
      expect(strings.commandsShortcutHint, 'Ctrl / Cmd + K · Comandi');

      // Sessions Sidebar
      expect(strings.sidebarFallbackFolderLabel, 'Sessioni');
      expect(strings.renameSessionDialogTitle, 'Rinomina sessione');
      expect(strings.sessionNameHint, 'Nome sessione...');
      expect(strings.sessionRenamedNotice('Test'), 'Sessione rinominata in "Test"');
      expect(strings.renameErrorNotice('Err'), 'Errore rinomina.');
      expect(strings.sessionDuplicatedNotice('s_2'), 'Sessione duplicata: s_2');
      expect(strings.duplicateErrorNotice('Err'), 'Errore duplicazione.');
      expect(strings.sidebarTitle, 'Sessioni');
      expect(strings.refreshSessionsTooltip, 'Aggiorna sessioni');
      expect(strings.newSessionTooltip, 'Nuova sessione');
      expect(strings.collapseSidebarTooltip, 'Collassa barra sessioni');
      expect(strings.searchSessionsHint, 'Cerca sessioni...');
      expect(strings.filterAll, 'Tutte');
      expect(strings.filterActive, 'Gestite');
      expect(strings.filterRepo, 'Questo repo');
      expect(strings.noSessionsMatchFilters, 'Nessuna sessione corrisponde ai filtri');
      expect(strings.noSessionsFound, 'Nessuna sessione trovata');
      expect(strings.pinnedSessionsHeader(3), 'FISSATE (3)');
      expect(strings.unknownFolderLabel, 'Cartella non nota');
      expect(strings.newSessionInFolderTooltip, 'Nuova sessione in questa cartella');
      expect(strings.repoInstructionsAction, 'Istruzioni repository');
      expect(strings.removeRepoFromSidebarAction, 'Rimuovi repository dal riquadro');
      expect(strings.sidebarErrorNotice('Err'), 'Errore.');
      expect(strings.settingsLabel, 'Impostazioni');
      expect(strings.commandPaletteTooltip, 'Comandi (Ctrl+K)');
      expect(strings.unpinAction, 'Rimuovi dai fissati');
      expect(strings.pinAction, 'Fissa in cima');
      expect(strings.renameAction, 'Rinomina');
      expect(strings.branchTreeAction, 'Albero rami');
      expect(strings.duplicateAction, 'Duplica');
      expect(strings.deleteSessionAction, 'Elimina sessione');
      expect(strings.sessionActionsTooltip, 'Azioni sessione');

      // Session Actions & Dialogs
      expect(strings.directoryNotAvailable('Err'), 'Cartella non disponibile.');
      expect(strings.newSessionDialogTitle, 'Nuova sessione');
      expect(strings.workingDirectoryLabel, 'Cartella di lavoro');
      expect(
        strings.browserPathNotice,
        'Nel browser inserisci il percorso locale raggiungibile dal daemon.',
      );
      expect(strings.chooseFolderAction, 'Scegli cartella');
      expect(strings.createAction, 'Crea');
      expect(strings.creationFailedNotice('Err'), 'Creazione non riuscita.');
      expect(strings.deleteSessionDialogTitle, 'Elimina sessione');
      expect(
        strings.deleteSessionConfirmBody('SessA'),
        'Sei sicuro di voler eliminare la sessione "SessA"?\n'
        'Tutti i messaggi e la cronologia della sessione verranno eliminati definitivamente.',
      );
      expect(strings.deleteAction, 'Elimina');
      expect(strings.sessionDeletedNotice('SessA'), 'Sessione "SessA" eliminata.');
      expect(strings.deletionFailedNotice('Err'), 'Eliminazione non riuscita.');
      expect(strings.removeRepoDialogTitle('RepoA'), 'Rimuovi repository "RepoA"');
      expect(
        strings.repoSessionsCountNotice(1),
        'Il repository contiene 1 sessione. Scegli cosa desideri fare:',
      );
      expect(
        strings.repoSessionsCountNotice(2),
        'Il repository contiene 2 sessioni. Scegli cosa desideri fare:',
      );
      expect(strings.removeOnlyFromViewTitle, 'Rimuovi solo dalla vista');
      expect(
        strings.removeOnlyFromViewSubtitle,
        'Nasconde il repository dal pannello sessioni. Nessuna sessione viene eliminata dal disco.',
      );
      expect(strings.deleteAllRepoSessionsTitle, 'Elimina repository e tutte le sessioni...');
      expect(
        strings.deleteAllRepoSessionsSubtitle,
        'Elimina definitivamente dal disco tutte le sessioni di questo repository.',
      );
      expect(strings.repoRemovedNotice('RepoA'), 'Repository "RepoA" rimosso dal riquadro.');
      expect(strings.restoreAction, 'Ripristina');
      expect(strings.allRepoSessionsDeletedNotice('RepoA'), 'Tutte le sessioni di "RepoA" sono state eliminate.');
      expect(strings.deletionErrorNotice('Err'), 'Errore durante l\'eliminazione.');
      expect(strings.warningDeletionTitle, 'ATTENZIONE: Eliminazione');
      expect(
        strings.deleteRepoWarningBody(3, '/path/repo'),
        'Stai per eliminare definitivamente tutte le 3 sessioni del repository:\n'
        '/path/repo\n\n'
        'Questa operazione cancellerà tutti i file di sessione e NON può essere annullata.\n\n'
        'Per confermare, digita "delete" nel campo sottostante:',
      );
      expect(strings.deleteAllAction, 'Elimina tutto');

      // Instruction File Dialog
      expect(strings.fileScanErrorNotice('Err'), 'Errore scansione file.');
      expect(strings.unsavedChangesTitle, 'Modifiche non salvate');
      expect(
        strings.unsavedChangesDiscardBody('A.md', 'B.md'),
        'Hai modifiche non salvate su A.md. Vuoi ignorarle e passare a B.md?',
      );
      expect(strings.discardChangesAction, 'Ignora modifiche');
      expect(strings.fileSavedNotice('A.md'), 'File A.md salvato con successo');
      expect(strings.saveErrorNotice('Err'), 'Errore salvataggio.');
      expect(strings.presentOnDiskBadge, 'Presente sul disco');
      expect(strings.newFileBadge, 'File nuovo');
      expect(strings.linesAndCharsCount(10, 200), '10 righe · 200 caratteri');
      expect(strings.enterInstructionsHint, 'Inserisci le istruzioni del repository qui...');
      expect(strings.syncedWithDiskStatus, 'Sincronizzato con il disco');
      expect(strings.generatingStatus, 'Generazione...');
      expect(strings.generateWithPiAction, 'Genera con Pi');
      expect(strings.saveChangesAction, 'Salva modifiche');
      expect(strings.createAndSaveFileAction, 'Crea e salva file');

      // Command Palette
      expect(strings.actionFailedNotice('Err'), 'Azione non riuscita.');
      expect(strings.paletteNewSessionTitle, 'Crea nuova sessione');
      expect(strings.paletteNewSessionSubtitle, 'Avvia una nuova sessione Pi');
      expect(strings.paletteCompactTitle, 'Compatta contesto');
      expect(strings.paletteCompactSubtitle, 'Esegui manual compaction per ridurre i token');
      expect(strings.paletteClearQueueTitle, 'Svuota coda');
      expect(strings.paletteClearQueueSubtitle, 'Rimuovi tutti i messaggi steer e follow-up in attesa');
      expect(strings.paletteInterruptTitle, 'Interrompi agente (Esc)');
      expect(strings.paletteInterruptSubtitle, 'Ferma il modello in esecuzione');
      expect(strings.paletteSwitchBrowserTitle, 'Mostra Web Browser');
      expect(strings.paletteSwitchBrowserSubtitle, 'Apri il browser web integrato nel pannello laterale');
      expect(strings.paletteSwitchGitTitle, 'Mostra modifiche Git');
      expect(strings.paletteSwitchGitSubtitle, 'Mostra il pannello delle modifiche Git nel pannello laterale');
      expect(strings.paletteSettingsTitle, 'Apri impostazioni');
      expect(strings.paletteSettingsSubtitle, 'Configura percorso Pi, timeout worker e aspetto');
      expect(strings.paletteSearchHint, 'Cerca un\'azione o comando...');
      expect(strings.paletteNoActionsFound, 'Nessuna azione trovata');

      // Agent Status
      expect(strings.agentStatusLabel(AgentStatus.idle), 'Inattivo');
      expect(strings.agentStatusLabel(AgentStatus.working), 'In esecuzione');
      expect(strings.agentStatusLabel(AgentStatus.retrying), 'Nuovo tentativo...');
      expect(strings.agentStatusLabel(AgentStatus.compacting), 'Compattazione...');
      expect(strings.agentStatusLabel(AgentStatus.awaitingUser), 'In attesa di input');
      expect(strings.agentStatusLabel(AgentStatus.settled), 'Completato');
      expect(strings.agentStatusLabel(AgentStatus.error), 'Errore');
      expect(strings.agentStatusLabel(AgentStatus.workerError), 'Worker arrestato');

      // Code & Diff
      expect(strings.copyAction, 'Copia');
      expect(strings.copiedAction, 'Copiato!');
    });

    test('ShellStrings English translations are natural and concise', () {
      const strings = AppStrings(AppLanguage.en);
      expect(strings.isItalian, isFalse);

      // Desktop Caption
      expect(strings.captionMinimize, 'Minimize');
      expect(strings.captionRestore, 'Restore window');
      expect(strings.captionMaximize, 'Maximize window');
      expect(strings.captionClose, 'Close window');

      // App Shell
      expect(strings.workspaceTitle, 'Workspace');
      expect(strings.closeWorkspaceTooltip, 'Close workspace');
      expect(strings.openSessionsTooltip, 'Open sessions');
      expect(strings.localPi, 'Local Pi');
      expect(strings.disconnected, 'Disconnected');
      expect(strings.commandsButtonLabel, 'Commands');
      expect(strings.togglePanelsTooltip, 'Show or hide panels');
      expect(strings.darkThemeTooltip, 'Dark theme');
      expect(strings.lightThemeTooltip, 'Light theme');
      expect(strings.settingsTooltip, 'Settings');
      expect(strings.modelAndSessionActionsTooltip, 'Model and session actions');
      expect(strings.reconnectingToDaemon, 'Reconnecting to daemon...');
      expect(
        strings.daemonUnreachableNotice,
        'Daemon unreachable. Sessions remain managed by Pi.',
      );
      expect(strings.retryAction, 'Retry');
      expect(strings.expandPaneTooltip('Chat'), 'Expand Chat panel');
      expect(strings.expandSessionsSidebarTooltip, 'Expand sessions sidebar');
      expect(strings.sessionsRailHeader, 'SESSIONS');
      expect(strings.recentSessionsHeader, 'Recent sessions');
      expect(strings.noFolderDisplay, 'No folder');
      expect(strings.newSessionHeroTitle, 'New\nsession.');
      expect(
        strings.welcomeDescription,
        'Choose a conversation or start working with Pi. Work continues even when you close the window.',
      );
      expect(strings.creatingSession, 'Creating...');
      expect(strings.newSessionAction, 'New session');
      expect(strings.browseSessionsAction, 'Browse sessions');
      expect(strings.searchCommandsAction, 'Search commands');
      expect(strings.commandsShortcutHint, 'Ctrl / Cmd + K · Commands');

      // Sessions Sidebar
      expect(strings.sidebarFallbackFolderLabel, 'Sessions');
      expect(strings.renameSessionDialogTitle, 'Rename Session');
      expect(strings.sessionNameHint, 'Session name...');
      expect(strings.sessionRenamedNotice('Test'), 'Session renamed to "Test"');
      expect(strings.renameErrorNotice('Err'), 'Rename error.');
      expect(strings.sessionDuplicatedNotice('s_2'), 'Session duplicated: s_2');
      expect(strings.duplicateErrorNotice('Err'), 'Duplicate error.');
      expect(strings.sidebarTitle, 'Sessions');
      expect(strings.refreshSessionsTooltip, 'Refresh sessions');
      expect(strings.newSessionTooltip, 'New Session');
      expect(strings.collapseSidebarTooltip, 'Collapse sessions sidebar');
      expect(strings.searchSessionsHint, 'Search sessions...');
      expect(strings.filterAll, 'All');
      expect(strings.filterActive, 'Managed');
      expect(strings.filterRepo, 'This repo');
      expect(strings.noSessionsMatchFilters, 'No sessions match filters');
      expect(strings.noSessionsFound, 'No sessions found');
      expect(strings.pinnedSessionsHeader(3), 'PINNED (3)');
      expect(strings.unknownFolderLabel, 'Unknown folder');
      expect(strings.newSessionInFolderTooltip, 'New session in this folder');
      expect(strings.repoInstructionsAction, 'Repository instructions');
      expect(strings.removeRepoFromSidebarAction, 'Remove repository from sidebar');
      expect(strings.sidebarErrorNotice('Err'), 'Error.');
      expect(strings.settingsLabel, 'Settings');
      expect(strings.commandPaletteTooltip, 'Command Palette (Ctrl+K)');
      expect(strings.unpinAction, 'Unpin');
      expect(strings.pinAction, 'Pin to top');
      expect(strings.renameAction, 'Rename');
      expect(strings.branchTreeAction, 'Branch tree');
      expect(strings.duplicateAction, 'Duplicate');
      expect(strings.deleteSessionAction, 'Delete session');
      expect(strings.sessionActionsTooltip, 'Session actions');

      // Agent Status
      expect(strings.agentStatusLabel(AgentStatus.idle), 'Idle');
      expect(strings.agentStatusLabel(AgentStatus.working), 'Working');
      expect(strings.agentStatusLabel(AgentStatus.retrying), 'Retrying...');
      expect(strings.agentStatusLabel(AgentStatus.compacting), 'Compacting...');
      expect(strings.agentStatusLabel(AgentStatus.awaitingUser), 'Awaiting input');
      expect(strings.agentStatusLabel(AgentStatus.settled), 'Completed');
      expect(strings.agentStatusLabel(AgentStatus.error), 'Error');
      expect(strings.agentStatusLabel(AgentStatus.workerError), 'Worker stopped');

      // Code & Diff
      expect(strings.copyAction, 'Copy');
      expect(strings.copiedAction, 'Copied!');
    });
  });

  group('Widget Localization Tests (Italian vs English)', () {
    Widget buildTestApp(Widget child, {AppLanguage language = AppLanguage.it}) {
      return ProviderScope(
        overrides: [
          appStringsProvider.overrideWithValue(AppStrings(language)),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('AgentStatusBadge renders Italian and English labels according to language', (tester) async {
      // Italian (default)
      await tester.pumpWidget(
        buildTestApp(
          const AgentStatusBadge(status: AgentStatus.working),
          language: AppLanguage.it,
        ),
      );
      expect(find.text('In esecuzione'), findsOneWidget);
      expect(find.text('Working'), findsNothing);

      // English
      await tester.pumpWidget(
        buildTestApp(
          const AgentStatusBadge(status: AgentStatus.working),
          language: AppLanguage.en,
        ),
      );
      expect(find.text('Working'), findsOneWidget);
      expect(find.text('In esecuzione'), findsNothing);
    });

    testWidgets('CodeBlock copy button renders Copia in IT and Copy in EN', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const CodeBlock(code: 'const x = 1;', language: 'dart'),
          language: AppLanguage.it,
        ),
      );
      expect(find.text('Copia'), findsOneWidget);

      await tester.pumpWidget(
        buildTestApp(
          const CodeBlock(code: 'const x = 1;', language: 'dart'),
          language: AppLanguage.en,
        ),
      );
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('DiffBlock copy button renders Copia in IT and Copy in EN', (tester) async {
      const diff = '@@ -1,1 +1,1 @@\n-old\n+new';
      await tester.pumpWidget(
        buildTestApp(
          const DiffBlock(diffText: diff, filename: 'test.dart'),
          language: AppLanguage.it,
        ),
      );
      expect(find.text('Copia'), findsOneWidget);

      await tester.pumpWidget(
        buildTestApp(
          const DiffBlock(diffText: diff, filename: 'test.dart'),
          language: AppLanguage.en,
        ),
      );
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('DesktopCaptionButtons renders Italian and English tooltips', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const DesktopCaptionButtons(),
          language: AppLanguage.it,
        ),
      );
      expect(find.byTooltip('Riduci a icona'), findsOneWidget);
      expect(find.byTooltip('Massimizza finestra'), findsOneWidget);
      expect(find.byTooltip('Chiudi finestra'), findsOneWidget);

      await tester.pumpWidget(
        buildTestApp(
          const DesktopCaptionButtons(),
          language: AppLanguage.en,
        ),
      );
      expect(find.byTooltip('Minimize'), findsOneWidget);
      expect(find.byTooltip('Maximize window'), findsOneWidget);
      expect(find.byTooltip('Close window'), findsOneWidget);
    });
  });
}
