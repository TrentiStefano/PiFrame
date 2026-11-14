import '../../domain/session/agent_status.dart';
import 'language_settings.dart';

extension ShellStrings on AppStrings {
  // Desktop Chrome Caption Buttons
  String get captionMinimize => isItalian ? 'Riduci a icona' : 'Minimize';
  String get captionRestore => isItalian ? 'Ripristina finestra' : 'Restore window';
  String get captionMaximize => isItalian ? 'Massimizza finestra' : 'Maximize window';
  String get captionClose => isItalian ? 'Chiudi finestra' : 'Close window';

  // App Shell
  String get workspaceTitle => isItalian ? 'Area di lavoro' : 'Workspace';
  String get closeWorkspaceTooltip => isItalian ? 'Chiudi workspace' : 'Close workspace';
  String get openSessionsTooltip => isItalian ? 'Apri sessioni' : 'Open sessions';
  String get localPi => isItalian ? 'Pi locale' : 'Local Pi';
  String get disconnected => isItalian ? 'Non connesso' : 'Disconnected';
  String get commandsButtonLabel => isItalian ? 'Comandi' : 'Commands';
  String get togglePanelsTooltip => isItalian ? 'Mostra o nascondi pannelli' : 'Show or hide panels';
  String get darkThemeTooltip => isItalian ? 'Tema scuro' : 'Dark theme';
  String get lightThemeTooltip => isItalian ? 'Tema chiaro' : 'Light theme';
  String get settingsTooltip => isItalian ? 'Impostazioni' : 'Settings';
  String get modelAndSessionActionsTooltip =>
      isItalian ? 'Modello e azioni sessione' : 'Model and session actions';
  String get reconnectingToDaemon =>
      isItalian ? 'Riconnessione al daemon in corso...' : 'Reconnecting to daemon...';
  String get daemonUnreachableNotice => isItalian
      ? 'Daemon non raggiungibile. Le sessioni restano gestite da Pi.'
      : 'Daemon unreachable. Sessions remain managed by Pi.';
  String get retryAction => isItalian ? 'Riprova' : 'Retry';
  String expandPaneTooltip(String pane) =>
      isItalian ? 'Espandi pannello $pane' : 'Expand $pane panel';
  String get expandSessionsSidebarTooltip =>
      isItalian ? 'Espandi barra sessioni' : 'Expand sessions sidebar';
  String get sessionsRailHeader => isItalian ? 'SESSIONI' : 'SESSIONS';
  String get recentSessionsHeader =>
      isItalian ? 'Sessioni recenti' : 'Recent sessions';
  String get noFolderDisplay => isItalian ? 'Nessuna cartella' : 'No folder';
  String get newSessionHeroTitle =>
      isItalian ? 'Nuova\nsessione.' : 'New\nsession.';
  String get welcomeDescription => isItalian
      ? 'Scegli una conversazione o inizia a lavorare con Pi. Il lavoro continua anche quando chiudi la finestra.'
      : 'Choose a conversation or start working with Pi. Work continues even when you close the window.';
  String get creatingSession => isItalian ? 'Creazione...' : 'Creating...';
  String get newSessionAction => isItalian ? 'Nuova sessione' : 'New session';
  String get browseSessionsAction =>
      isItalian ? 'Esplora sessioni' : 'Browse sessions';
  String get searchCommandsAction =>
      isItalian ? 'Cerca nei comandi' : 'Search commands';
  String get commandsShortcutHint =>
      isItalian ? 'Ctrl / Cmd + K · Comandi' : 'Ctrl / Cmd + K · Commands';

  // Sessions Sidebar
  String get sidebarFallbackFolderLabel =>
      isItalian ? 'Sessioni' : 'Sessions';
  String get renameSessionDialogTitle =>
      isItalian ? 'Rinomina sessione' : 'Rename Session';
  String get sessionNameHint =>
      isItalian ? 'Nome sessione...' : 'Session name...';
  String sessionRenamedNotice(String newName) =>
      isItalian ? 'Sessione rinominata in "$newName"' : 'Session renamed to "$newName"';
  String renameErrorNotice(Object e) =>
      isItalian ? 'Errore rinomina: $e' : 'Rename error: $e';
  String sessionDuplicatedNotice(String newSid) =>
      isItalian ? 'Sessione duplicata: $newSid' : 'Session duplicated: $newSid';
  String duplicateErrorNotice(Object e) =>
      isItalian ? 'Errore duplicazione: $e' : 'Duplicate error: $e';
  String get sidebarTitle => isItalian ? 'Sessioni' : 'Sessions';
  String get refreshSessionsTooltip =>
      isItalian ? 'Aggiorna sessioni' : 'Refresh sessions';
  String get newSessionTooltip =>
      isItalian ? 'Nuova sessione' : 'New Session';
  String get collapseSidebarTooltip =>
      isItalian ? 'Collassa barra sessioni' : 'Collapse sessions sidebar';
  String get searchSessionsHint =>
      isItalian ? 'Cerca sessioni...' : 'Search sessions...';
  String get filterAll => isItalian ? 'Tutte' : 'All';
  String get filterActive => isItalian ? 'Gestite' : 'Managed';
  String get filterRepo => isItalian ? 'Questo repo' : 'This repo';
  String get noSessionsMatchFilters =>
      isItalian ? 'Nessuna sessione corrisponde ai filtri' : 'No sessions match filters';
  String get noSessionsFound =>
      isItalian ? 'Nessuna sessione trovata' : 'No sessions found';
  String pinnedSessionsHeader(int count) =>
      isItalian ? 'FISSATE ($count)' : 'PINNED ($count)';
  String get unknownFolderLabel =>
      isItalian ? 'Cartella non nota' : 'Unknown folder';
  String get newSessionInFolderTooltip =>
      isItalian ? 'Nuova sessione in questa cartella' : 'New session in this folder';
  String get repoInstructionsAction =>
      isItalian ? 'Istruzioni repository' : 'Repository instructions';
  String get removeRepoFromSidebarAction =>
      isItalian ? 'Rimuovi repository dal riquadro' : 'Remove repository from sidebar';
  String sidebarErrorNotice(Object err) =>
      isItalian ? 'Errore: $err' : 'Error: $err';
  String get settingsLabel => isItalian ? 'Impostazioni' : 'Settings';
  String get commandPaletteTooltip =>
      isItalian ? 'Comandi (Ctrl+K)' : 'Command Palette (Ctrl+K)';
  String get unpinAction => isItalian ? 'Rimuovi dai fissati' : 'Unpin';
  String get pinAction => isItalian ? 'Fissa in cima' : 'Pin to top';
  String get renameAction => isItalian ? 'Rinomina' : 'Rename';
  String get branchTreeAction => isItalian ? 'Albero rami' : 'Branch tree';
  String get duplicateAction => isItalian ? 'Duplica' : 'Duplicate';
  String get deleteSessionAction =>
      isItalian ? 'Elimina sessione' : 'Delete session';
  String get sessionActionsTooltip =>
      isItalian ? 'Azioni sessione' : 'Session actions';

  // Session Actions & Dialogs
  String directoryNotAvailable(Object e) =>
      isItalian ? 'Cartella non disponibile: $e' : 'Directory not available: $e';
  String get newSessionDialogTitle =>
      isItalian ? 'Nuova sessione' : 'New session';
  String get workingDirectoryLabel =>
      isItalian ? 'Cartella di lavoro' : 'Working directory';
  String get browserPathNotice => isItalian
      ? 'Nel browser inserisci il percorso locale raggiungibile dal daemon.'
      : 'In the browser, enter a local path reachable by the daemon.';
  String get chooseFolderAction =>
      isItalian ? 'Scegli cartella' : 'Choose folder';
  String get createAction => isItalian ? 'Crea' : 'Create';
  String creationFailedNotice(Object e) =>
      isItalian ? 'Creazione non riuscita: $e' : 'Creation failed: $e';
  String get deleteSessionDialogTitle =>
      isItalian ? 'Elimina sessione' : 'Delete session';
  String deleteSessionConfirmBody(String sessionName) => isItalian
      ? 'Sei sicuro di voler eliminare la sessione "$sessionName"?\n'
          'Tutti i messaggi e la cronologia della sessione verranno eliminati definitivamente.'
      : 'Are you sure you want to delete session "$sessionName"?\n'
          'All messages and history for this session will be permanently deleted.';
  String get deleteAction => isItalian ? 'Elimina' : 'Delete';
  String sessionDeletedNotice(String sessionName) =>
      isItalian ? 'Sessione "$sessionName" eliminata.' : 'Session "$sessionName" deleted.';
  String deletionFailedNotice(Object e) =>
      isItalian ? 'Eliminazione non riuscita: $e' : 'Deletion failed: $e';
  String removeRepoDialogTitle(String repoName) =>
      isItalian ? 'Rimuovi repository "$repoName"' : 'Remove repository "$repoName"';
  String repoSessionsCountNotice(int count) => isItalian
      ? 'Il repository contiene $count session${count == 1 ? 'e' : 'i'}. Scegli cosa desideri fare:'
      : 'The repository contains $count session${count == 1 ? '' : 's'}. Choose what you would like to do:';
  String get removeOnlyFromViewTitle =>
      isItalian ? 'Rimuovi solo dalla vista' : 'Remove from view only';
  String get removeOnlyFromViewSubtitle => isItalian
      ? 'Nasconde il repository dal pannello sessioni. Nessuna sessione viene eliminata dal disco.'
      : 'Hides the repository from the sessions panel. No sessions are deleted from disk.';
  String get deleteAllRepoSessionsTitle => isItalian
      ? 'Elimina repository e tutte le sessioni...'
      : 'Delete repository and all sessions...';
  String get deleteAllRepoSessionsSubtitle => isItalian
      ? 'Elimina definitivamente dal disco tutte le sessioni di questo repository.'
      : 'Permanently delete all sessions for this repository from disk.';
  String repoRemovedNotice(String repoName) => isItalian
      ? 'Repository "$repoName" rimosso dal riquadro.'
      : 'Repository "$repoName" removed from sidebar.';
  String get restoreAction => isItalian ? 'Ripristina' : 'Restore';
  String allRepoSessionsDeletedNotice(String repoName) => isItalian
      ? 'Tutte le sessioni di "$repoName" sono state eliminate.'
      : 'All sessions for "$repoName" have been deleted.';
  String deletionErrorNotice(Object e) =>
      isItalian ? 'Errore durante l\'eliminazione: $e' : 'Error during deletion: $e';
  String get warningDeletionTitle =>
      isItalian ? 'ATTENZIONE: Eliminazione' : 'WARNING: Deletion';
  String deleteRepoWarningBody(int count, String folder) => isItalian
      ? 'Stai per eliminare definitivamente tutte le $count sessioni del repository:\n'
          '$folder\n\n'
          'Questa operazione cancellerà tutti i file di sessione e NON può essere annullata.\n\n'
          'Per confermare, digita "delete" nel campo sottostante:'
      : 'You are about to permanently delete all $count sessions of the repository:\n'
          '$folder\n\n'
          'This operation will permanently delete all session files and CANNOT be undone.\n\n'
          'To confirm, type "delete" in the field below:';
  String get deleteAllAction => isItalian ? 'Elimina tutto' : 'Delete all';

  // Instruction File Dialog
  String fileScanErrorNotice(Object e) =>
      isItalian ? 'Errore scansione file: $e' : 'File scan error: $e';
  String get unsavedChangesTitle =>
      isItalian ? 'Modifiche non salvate' : 'Unsaved changes';
  String unsavedChangesDiscardBody(String selectedFile, String fileName) => isItalian
      ? 'Hai modifiche non salvate su $selectedFile. Vuoi ignorarle e passare a $fileName?'
      : 'You have unsaved changes in $selectedFile. Do you want to discard them and switch to $fileName?';
  String get discardChangesAction =>
      isItalian ? 'Ignora modifiche' : 'Discard changes';
  String fileSavedNotice(String selectedFile) =>
      isItalian ? 'File $selectedFile salvato con successo' : 'File $selectedFile saved successfully';
  String saveErrorNotice(Object e) =>
      isItalian ? 'Errore salvataggio: $e' : 'Save error: $e';
  String generateInstructionsPrompt(String selectedFile) => isItalian
      ? 'Analizza la struttura del repository in questa cartella e genera il contenuto completo per il file $selectedFile.\n'
          'Includi: Panoramica dell\'architettura, Comandi di build, test e linting, Convenzioni di codice e Linee guida operative per gli agenti.\n'
          'Restituisci solo ed esclusivamente il contenuto markdown formattato per il file.'
      : 'Analyze the structure of the repository in this folder and generate the complete content for the file $selectedFile.\n'
          'Include: Architecture overview, Build, test and linting commands, Code conventions and Operational guidelines for agents.\n'
          'Return exclusively the formatted markdown content for the file.';
  String generateInstructionsSuccessNotice(String selectedFile) => isItalian
      ? 'Istruzioni per $selectedFile generate con successo dall\'agente Pi'
      : 'Instructions for $selectedFile generated successfully by Pi agent';
  String generateInstructionsErrorNotice(Object e) =>
      isItalian ? 'Errore generazione con Pi: $e' : 'Pi generation error: $e';
  String get presentOnDiskBadge =>
      isItalian ? 'Presente sul disco' : 'Present on disk';
  String get newFileBadge =>
      isItalian ? 'File nuovo' : 'New file';
  String linesAndCharsCount(int lineCount, int charCount) => isItalian
      ? '$lineCount righe · $charCount caratteri'
      : '$lineCount lines · $charCount characters';
  String get enterInstructionsHint => isItalian
      ? 'Inserisci le istruzioni del repository qui...'
      : 'Enter repository instructions here...';
  String get syncedWithDiskStatus =>
      isItalian ? 'Sincronizzato con il disco' : 'Synced with disk';
  String get generatingStatus =>
      isItalian ? 'Generazione...' : 'Generating...';
  String get generateWithPiAction =>
      isItalian ? 'Genera con Pi' : 'Generate with Pi';
  String get saveChangesAction =>
      isItalian ? 'Salva modifiche' : 'Save changes';
  String get createAndSaveFileAction =>
      isItalian ? 'Crea e salva file' : 'Create & save file';
  String get softwareProjectLabel =>
      isItalian ? 'Progetto software' : 'Software Project';
  String get flutterBuildOrRunLabel =>
      isItalian ? 'flutter build (o flutter run)' : 'flutter build (or flutter run)';

  // Fallback markdown templates
  String fallbackAgentTitle(String folderName) =>
      isItalian ? '# Istruzioni per gli agenti ($folderName)\n' : '# Agent Instructions ($folderName)\n';
  String get fallbackAgentIntro => isItalian
      ? 'Questo file contiene le linee guida operative generate per l\'agente Pi in questo repository.\n'
      : 'This file contains operational guidelines generated for the Pi agent in this repository.\n';
  String get fallbackAgentOverview =>
      isItalian ? '## Panoramica del progetto' : '## Project Overview';
  String get fallbackAgentTechStack =>
      isItalian ? 'Stack tecnologico' : 'Tech Stack';
  String get fallbackAgentCoreModules =>
      isItalian ? 'Moduli principali' : 'Core Modules';
  String get fallbackAgentCommandsTitle =>
      isItalian ? '\n## Comandi di sviluppo e verifica' : '\n## Development & Verification Commands';
  String get fallbackAgentCommandsIntro => isItalian
      ? 'Esegui sempre i comandi di verifica dopo aver apportato modifiche:'
      : 'Always run verification commands after making changes:';
  String get fallbackAgentGuidelinesTitle =>
      isItalian ? '\n## Linee guida operative' : '\n## Operational Guidelines';
  String get fallbackAgentRule1 => isItalian
      ? '1. **Integrità del codice**: Mantieni sempre pulita la base di codice e rispetta le convenzioni del progetto.'
      : '1. **Code Integrity**: Keep the codebase clean and adhere to project conventions.';
  String get fallbackAgentRule2 => isItalian
      ? '2. **Verifica dei test**: Assicurati che l\'intera suite di test passi prima di completare i task.'
      : '2. **Test Verification**: Ensure the entire test suite passes before completing tasks.';
  String get fallbackAgentRule3 => isItalian
      ? '3. **Architettura**: Non introdurre dipendenze non necessarie e mantieni i componenti modulari.'
      : '3. **Architecture**: Do not introduce unnecessary dependencies and keep components modular.';
  String get fallbackAgentRule4 => isItalian
      ? '4. **Sicurezza e robustezza**: Gestisci sempre gli errori in modo esplicito e prevedi fallback trasparenti.'
      : '4. **Safety & Robustness**: Always handle errors explicitly and provide transparent fallbacks.';
  String fallbackDefaultTitle(String targetFileName, String folderName) =>
      isItalian ? '# Istruzioni per $targetFileName ($folderName)\n' : '# Instructions for $targetFileName ($folderName)\n';
  String get fallbackDefaultOverview =>
      isItalian ? '## Panoramica' : '## Overview';
  String get fallbackDefaultTech =>
      isItalian ? 'Tecnologie' : 'Technologies';
  String get fallbackDefaultCommandsTitle =>
      isItalian ? '\n## Comandi principali' : '\n## Key Commands';
  String get fallbackDefaultRulesTitle =>
      isItalian ? '\n## Regole del repository' : '\n## Repository Rules';
  String get fallbackDefaultRule1 => isItalian
      ? '- Rispetta lo stile e le convenzioni del codice esistente.'
      : '- Respect existing code style and conventions.';
  String get fallbackDefaultRule2 => isItalian
      ? '- Non committare file di build o credenziali.'
      : '- Do not commit build artifacts or credentials.';

  String fallbackProjectTitle(String targetFileName) =>
      isItalian ? '# Istruzioni di progetto per $targetFileName\n' : '# Project Instructions for $targetFileName\n';
  String fallbackProjectHeader(String folderName) =>
      isItalian ? '## Progetto: $folderName' : '## Project: $folderName';
  String get fallbackProjectCommands =>
      isItalian ? '\n## Comandi' : '\n## Commands';
  String get fallbackProjectRules =>
      isItalian ? '\n## Regole' : '\n## Rules';
  String get fallbackProjectRuleDetail => isItalian
      ? '- Rispetta la struttura del repository e testa le modifiche prima del commit.'
      : '- Respect repository structure and test changes before commit.';

  // Command Palette
  String actionFailedNotice(Object error) =>
      isItalian ? 'Azione non riuscita: $error' : 'Action failed: $error';
  String get paletteNewSessionTitle =>
      isItalian ? 'Crea nuova sessione' : 'Create new session';
  String get paletteNewSessionSubtitle =>
      isItalian ? 'Avvia una nuova sessione Pi' : 'Start a new Pi session';
  String get paletteCompactTitle =>
      isItalian ? 'Compatta contesto' : 'Compact context';
  String get paletteCompactSubtitle => isItalian
      ? 'Esegui manual compaction per ridurre i token'
      : 'Run manual compaction to reduce tokens';
  String get paletteClearQueueTitle =>
      isItalian ? 'Svuota coda' : 'Clear queue';
  String get paletteClearQueueSubtitle => isItalian
      ? 'Rimuovi tutti i messaggi steer e follow-up in attesa'
      : 'Remove all pending steer and follow-up messages';
  String get paletteInterruptTitle =>
      isItalian ? 'Interrompi agente (Esc)' : 'Interrupt agent (Esc)';
  String get paletteInterruptSubtitle =>
      isItalian ? 'Ferma il modello in esecuzione' : 'Stop running model';
  String get paletteSwitchBrowserTitle =>
      isItalian ? 'Mostra Web Browser' : 'Show Web Browser';
  String get paletteSwitchBrowserSubtitle => isItalian
      ? 'Apri il browser web integrato nel pannello laterale'
      : 'Open embedded web browser in side panel';
  String get paletteSwitchGitTitle =>
      isItalian ? 'Mostra modifiche Git' : 'Show Git Changes';
  String get paletteSwitchGitSubtitle => isItalian
      ? 'Mostra il pannello delle modifiche Git nel pannello laterale'
      : 'Show Git changes panel in side panel';
  String get paletteSettingsTitle =>
      isItalian ? 'Apri impostazioni' : 'Open Settings';
  String get paletteSettingsSubtitle => isItalian
      ? 'Configura percorso Pi, timeout worker e aspetto'
      : 'Configure Pi path, worker timeouts, and appearance';
  String get paletteSearchHint => isItalian
      ? 'Cerca un\'azione o comando...'
      : 'Search action or command...';
  String get paletteNoActionsFound =>
      isItalian ? 'Nessuna azione trovata' : 'No actions found';

  // Agent Status Badge
  String agentStatusLabel(AgentStatus status) {
    if (isItalian) {
      return status.label;
    }
    return switch (status) {
      AgentStatus.idle => 'Idle',
      AgentStatus.working => 'Working',
      AgentStatus.retrying => 'Retrying...',
      AgentStatus.compacting => 'Compacting...',
      AgentStatus.awaitingUser => 'Awaiting input',
      AgentStatus.settled => 'Completed',
      AgentStatus.error => 'Error',
      AgentStatus.workerError => 'Worker stopped',
    };
  }

  // Code & Diff blocks
  String get copyAction => isItalian ? 'Copia' : 'Copy';
  String get copiedAction => isItalian ? 'Copiato!' : 'Copied!';
}
