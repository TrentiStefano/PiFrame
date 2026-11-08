import 'language_settings.dart';

/// Workspace, session changes, browser, and metrics internationalized strings.
extension WorkspaceStrings on AppStrings {
  // ---------------------------------------------------------------------------
  // Terminal
  // ---------------------------------------------------------------------------
  String terminalStartingSession(String displayDir) => isItalian
      ? 'Avvio sessione terminale in: $displayDir\r\n\r\n'
      : 'Starting terminal session in: $displayDir\r\n\r\n';

  String terminalProcessTerminated(int? code) => isItalian
      ? '\r\n[Processo terminato con codice $code]\r\n'
      : '\r\n[Process terminated with exit code $code]\r\n';

  String terminalCannotStartProcess(String executable, Object error) => isItalian
      ? 'Impossibile avviare il processo della shell ($executable): $error\r\n'
      : 'Cannot start shell process ($executable): $error\r\n';

  String get terminalNoOpenTerminals =>
      isItalian ? 'Nessun terminale aperto' : 'No open terminals';

  String get terminalOpenNew =>
      isItalian ? 'Apri nuovo terminale' : 'Open new terminal';

  String get terminalNewTabTooltip =>
      isItalian ? 'Nuovo terminale' : 'New terminal';

  String terminalNewWslTab(String distro) => isItalian
      ? 'Nuovo terminale WSL ($distro)'
      : 'New WSL terminal ($distro)';

  String get terminalNewPowerShellTab => isItalian
      ? 'Nuovo terminale (PowerShell)'
      : 'New terminal (PowerShell)';

  String get terminalInterruptTooltip => isItalian
      ? 'Interrompi processo (Ctrl+C)'
      : 'Stop process (Ctrl+C)';

  String get terminalClearTooltip =>
      isItalian ? 'Pulisci schermo (Clear)' : 'Clear screen';

  String get terminalNativeAppTooltip => isItalian
      ? 'Apri nel terminale nativo (OS)'
      : 'Open in native terminal (OS)';

  String get terminalCollapseTooltip =>
      isItalian ? 'Collassa in basso' : 'Collapse down';

  String get terminalCloseTooltip =>
      isItalian ? 'Chiudi terminale' : 'Close terminal';

  // ---------------------------------------------------------------------------
  // Repository Workspace: Files, Editor & General Dialogs
  // ---------------------------------------------------------------------------
  String get unsavedChangesTitle =>
      isItalian ? 'Modifiche non salvate' : 'Unsaved changes';

  String get unsavedChangesContentCanSave => isItalian
      ? 'Salva o scarta le modifiche prima di lasciare questa sessione.'
      : 'Save or discard changes before leaving this session.';

  String unsavedChangesContentBlocked(String blockedReason) => isItalian
      ? 'Salvataggio non disponibile: $blockedReason. Puoi scartare le modifiche o annullare.'
      : 'Saving not available: $blockedReason. You can discard changes or cancel.';

  String get readOnlySessionLower =>
      isItalian ? 'sessione in sola lettura' : 'read-only session';

  String get readOnlySessionCapital =>
      isItalian ? 'Sessione in sola lettura' : 'Read-only session';

  String get daemonNotConnectedLower =>
      isItalian ? 'daemon non connesso' : 'daemon not connected';

  String get daemonNotConnectedCapital =>
      isItalian ? 'Daemon non connesso' : 'Daemon not connected';

  String get discard => isItalian ? 'Scarta' : 'Discard';

  String get fileModifiedExternallyTitle =>
      isItalian ? 'File modificato altrove' : 'File modified externally';

  String fileModifiedExternallyContent(String path) => isItalian
      ? '$path è cambiato su disco. Il testo locale resta intatto.'
      : '$path has changed on disk. Local text remains intact.';

  String get keepChanges =>
      isItalian ? 'Mantieni modifiche' : 'Keep changes';

  String get reloadFromDisk =>
      isItalian ? 'Ricarica disco' : 'Reload from disk';

  String get overwriteExplicitly =>
      isItalian ? 'Sovrascrivi esplicitamente' : 'Overwrite explicitly';

  String saveFailed(Object error) => isItalian
      ? 'Salvataggio non riuscito: $error'
      : 'Save failed: $error';

  String get loadingFiles =>
      isItalian ? 'Caricamento file...' : 'Loading files...';

  String get noFilesAvailable =>
      isItalian ? 'Nessun file disponibile.' : 'No files available.';

  String get searchFilesHint =>
      isItalian ? 'Cerca file...' : 'Search files...';

  String get clearSearchTooltip =>
      isItalian ? 'Cancella ricerca' : 'Clear search';

  String noFilesFound(String query) => isItalian
      ? 'Nessun file trovato per "$query"'
      : 'No files found for "$query"';

  String addedFileToChat(String path) => isItalian
      ? 'Aggiunto @$path alla chat'
      : 'Added @$path to chat';

  String get selectAFile =>
      isItalian ? 'Seleziona un file' : 'Select a file';

  String get backToFilesTooltip =>
      isItalian ? 'Torna ai file' : 'Back to files';

  String get modifiedBadge =>
      isItalian ? 'MODIFICATO' : 'MODIFIED';

  String get addFileToChatTooltip =>
      isItalian ? 'Aggiungi file alla chat' : 'Add file to chat';

  String get editMarkdownSourceTooltip => isItalian
      ? 'Modifica markdown sorgente'
      : 'Edit markdown source';

  String get viewMarkdownPreviewTooltip => isItalian
      ? 'Visualizza anteprima formattata'
      : 'View formatted preview';

  String get searchInFileTooltip =>
      isItalian ? 'Cerca nel file (Ctrl+F)' : 'Search in file (Ctrl+F)';

  String get closeFileTooltip =>
      isItalian ? 'Chiudi file' : 'Close file';

  String get readOnlyBlockedReason =>
      isItalian ? 'Sola lettura' : 'Read-only';

  String get fileContentHint =>
      isItalian ? 'Contenuto file' : 'File content';

  String savingDisabledReason(String status) => isItalian
      ? 'Salvataggio disabilitato: $status.'
      : 'Saving disabled: $status.';

  String get searchInFileHint =>
      isItalian ? 'Cerca nel file...' : 'Search in file...';

  String searchResultsCount(int current, int total) =>
      isItalian ? '$current di $total' : '$current of $total';

  String get zeroResults =>
      isItalian ? '0 risultati' : '0 results';

  String get previousMatchTooltip =>
      isItalian ? 'Precedente (Shift+Enter)' : 'Previous (Shift+Enter)';

  String get nextMatchTooltip =>
      isItalian ? 'Successivo (Enter)' : 'Next (Enter)';

  String get matchCaseTooltip =>
      isItalian ? 'Distingui maiuscole/minuscole' : 'Match case';

  String get closeFileSearchTooltip =>
      isItalian ? 'Chiudi (Esc)' : 'Close (Esc)';

  String get openNativeTerminalTooltip => isItalian
      ? 'Apri terminale nativo (OS)'
      : 'Open native terminal (OS)';

  String get hideTerminalTooltip =>
      isItalian ? 'Nascondi terminale' : 'Hide terminal';

  String get integratedTerminalTooltip =>
      isItalian ? 'Terminale integrato' : 'Integrated terminal';

  String get collapseAllFoldersTooltip =>
      isItalian ? 'Collassa tutte le cartelle' : 'Collapse all folders';

  String get expandAllFoldersTooltip =>
      isItalian ? 'Espandi tutte le cartelle' : 'Expand all folders';

  String get refreshFilesTooltip =>
      isItalian ? 'Aggiorna file' : 'Refresh files';

  String get collapseRepoPanelTooltip => isItalian
      ? 'Collassa pannello Repository'
      : 'Collapse Repository panel';

  String get fileListLimitedNotice => isItalian
      ? 'Elenco file limitato dal daemon.'
      : 'File list limited by daemon.';

  String get repositoryDaemonOutdatedError => isItalian
      ? 'Daemon obsoleto: esegui `pnpm run build:agentd`, ricostruisci PiFrame e riavvia il daemon solo quando nessun worker Pi è attivo.'
      : 'Daemon outdated: run `pnpm run build:agentd`, rebuild PiFrame, and restart the daemon only when no Pi workers are active.';

  String get terminalBadge =>
      isItalian ? 'TERMINALE' : 'TERMINAL';

  String get expandTerminalTooltip =>
      isItalian ? 'Espandi terminale' : 'Expand terminal';

  String get closeTerminalTooltip =>
      isItalian ? 'Chiudi terminale' : 'Close terminal';

  // ---------------------------------------------------------------------------
  // Git Changes Pane
  // ---------------------------------------------------------------------------
  String gitOperationFailed(Object error) => isItalian
      ? 'Operazione Git non riuscita: $error'
      : 'Git operation failed: $error';

  String get closeDiffTooltip =>
      isItalian ? 'Chiudi diff' : 'Close diff';

  String get noDifferencesFound =>
      isItalian ? 'Nessuna differenza trovata.' : 'No differences found.';

  String diffUnavailable(Object error) => isItalian
      ? 'Diff non disponibile: $error'
      : 'Diff unavailable: $error';

  String get diffUnavailableShort =>
      isItalian ? 'Diff non disponibile.' : 'Diff unavailable.';

  String get discardAllChangesTitle =>
      isItalian ? 'Annullare tutte le modifiche?' : 'Discard all changes?';

  String get discardAllChangesWarning => isItalian
      ? 'L’operazione rimuove modifiche staged e unstaged.'
      : 'This operation removes staged and unstaged changes.';

  String get discardChangesBtn =>
      isItalian ? 'Annulla modifiche' : 'Discard changes';

  String get commitStagedFilesTitle =>
      isItalian ? 'Commit dei file staged' : 'Commit staged files';

  String commitDialogDetails({
    required String root,
    required String branch,
    required int count,
    required String filesPreview,
    required int remaining,
  }) =>
      isItalian
          ? 'Repository: $root · ramo: $branch\nFile revisionati ($count): $filesPreview${remaining > 0 ? ' (+$remaining altri)' : ''}'
          : 'Repository: $root · branch: $branch\nReviewed files ($count): $filesPreview${remaining > 0 ? ' (+$remaining more)' : ''}';

  String get commitMessageLabel =>
      isItalian ? 'Messaggio commit' : 'Commit message';

  String get commitAction => 'Commit';

  String unstageFileTooltip(String path) => isItalian
      ? 'Togli dallo stage $path'
      : 'Unstage $path';

  String stageFileTooltip(String path) => isItalian
      ? 'Metti in stage $path'
      : 'Stage $path';

  String discardFileTooltip(String path) => isItalian
      ? 'Annulla modifiche a $path'
      : 'Discard changes to $path';

  String get switchToWebBrowserTooltip =>
      isItalian ? 'Passa a Web Browser' : 'Switch to Web Browser';

  String get refreshGitStatusTooltip =>
      isItalian ? 'Aggiorna stato Git' : 'Refresh Git status';

  String get collapseGitPanelTooltip => isItalian
      ? 'Collassa pannello Git Changes'
      : 'Collapse Git Changes panel';

  String writesDisabledReadOnly(String? reason) => isItalian
      ? 'Scritture disabilitate: ${reason ?? "sessione in sola lettura"}'
      : 'Writes disabled: ${reason ?? "read-only session"}';

  String get writesDisabledPiWorking => isItalian
      ? 'Scritture disabilitate mentre Pi sta lavorando.'
      : 'Writes disabled while Pi is working.';

  String get connectingToGit =>
      isItalian ? 'Collegamento a Git...' : 'Connecting to Git...';

  String get noGitRepository =>
      isItalian ? 'Nessun repository Git.' : 'No Git repository.';

  String gitFilesCount(int count) => isItalian
      ? '$count file'
      : '$count ${count == 1 ? "file" : "files"}';

  String get workingTreeClean =>
      isItalian ? 'Working tree pulito' : 'Working tree clean';

  String get stagedChangesSectionTitle =>
      isItalian ? 'Modifiche preparate (Staged)' : 'Staged changes';

  String get stagedChangesSectionUpper =>
      isItalian ? 'MODIFICHE PREPARATE (STAGED)' : 'STAGED CHANGES';

  String get unstageAllTooltip =>
      isItalian ? 'Togli tutti dallo stage' : 'Unstage all';

  String get noStagedFiles =>
      isItalian ? 'Nessun file preparato.' : 'No staged files.';

  String get changesSectionTitle =>
      isItalian ? 'Modifiche (Changes)' : 'Changes';

  String get changesSectionUpper =>
      isItalian ? 'MODIFICHE (CHANGES)' : 'CHANGES';

  String get stageAllTooltip =>
      isItalian ? 'Metti tutti in stage' : 'Stage all';

  String get noUnstagedChanges => isItalian
      ? 'Nessuna modifica non preparata.'
      : 'No unstaged changes.';

  String commitButtonLabel(int count) => 'Commit ($count)';

  String get addPathToChat =>
      isItalian ? 'Aggiungi alla chat' : 'Add to chat';

  String get copyPath =>
      isItalian ? 'Copia percorso' : 'Copy path';

  String pathCopied(String path) => isItalian
      ? 'Percorso copiato: $path'
      : 'Path copied: $path';

  // Git origin labels
  String get gitOriginPiAndManual => isItalian
      ? 'Tool Pi + salvataggio PiFrame'
      : 'Pi tool + PiFrame save';

  String get gitOriginPiTool => isItalian
      ? 'Tool Pi ha scritto il percorso'
      : 'Pi tool wrote path';

  String get gitOriginManualSave => isItalian
      ? 'Salvato da te in PiFrame'
      : 'Saved by you in PiFrame';

  String get gitOriginUndetermined => isItalian
      ? 'Origine non determinata'
      : 'Undetermined origin';

  // ---------------------------------------------------------------------------
  // Session Changes Pane & Diff Viewer
  // ---------------------------------------------------------------------------
  String get cannotLoadFileDiff => isItalian
      ? 'Impossibile caricare il diff del file.'
      : 'Unable to load file diff.';

  String get loadingDiff =>
      isItalian ? 'Caricamento diff...' : 'Loading diff...';

  String get noDiffToShow => isItalian
      ? 'Nessuna differenza da mostrare.'
      : 'No differences to show.';

  String get linesExpanded =>
      isItalian ? 'Linee espanse' : 'Lines expanded';

  String moreLines(int count) => isItalian
      ? '+$count more lines'
      : '+$count more lines';

  String get twoColumnDiffTooltip => isItalian
      ? 'Passa a visualizzazione a 2 colonne'
      : 'Switch to 2-column view';

  String get singleColumnDiffTooltip => isItalian
      ? 'Passa a visualizzazione a colonna singola'
      : 'Switch to single-column view';

  String get refreshSessionChangesTooltip =>
      isItalian ? 'Aggiorna modifiche' : 'Refresh changes';

  String get closeReviewTooltip =>
      isItalian ? 'Chiudi revisione' : 'Close review';

  String get noModifiedFilesInSession => isItalian
      ? 'Nessun file modificato in questa sessione.'
      : 'No files modified in this session.';

  // ---------------------------------------------------------------------------
  // Browser Pane & Service
  // ---------------------------------------------------------------------------
  String get browserDefaultGreeting => isItalian
      ? 'Benvenuto nel browser integrato di PiFrame.'
      : 'Welcome to PiFrame integrated browser.';

  String browserSearchTitle(String query) =>
      isItalian ? 'Ricerca: $query' : 'Search: $query';

  String get browserLoading =>
      isItalian ? 'Caricamento...' : 'Loading...';

  String cannotOpenSystemBrowser(Object error) => isItalian
      ? 'Impossibile aprire il browser di sistema: $error'
      : 'Cannot open system browser: $error';

  String get pageLinkAddedToComposer => isItalian
      ? 'Link della pagina aggiunto al prompt del composer.'
      : 'Page link added to composer prompt.';

  String get urlCopiedToClipboard => isItalian
      ? 'URL copiato negli appunti.'
      : 'URL copied to clipboard.';

  String get openChromiumDevToolsTooltip => isItalian
      ? 'Apri DevTools di Chromium (F12)'
      : 'Open Chromium DevTools (F12)';

  String get sendToChatComposerTooltip => isItalian
      ? 'Invia al Chat Composer'
      : 'Send to Chat Composer';

  String get copyUrlTooltip =>
      isItalian ? 'Copia URL' : 'Copy URL';

  String get openInSystemBrowserTooltip => isItalian
      ? 'Apri nel browser di sistema'
      : 'Open in system browser';

  String get collapseBrowserPanelTooltip => isItalian
      ? 'Collassa pannello Web Browser'
      : 'Collapse Web Browser panel';

  String get newBrowserTab =>
      isItalian ? 'Nuova scheda' : 'New tab';

  String get browserBackTooltip =>
      isItalian ? 'Indietro' : 'Back';

  String get browserForwardTooltip =>
      isItalian ? 'Avanti' : 'Forward';

  String get browserReloadTooltip =>
      isItalian ? 'Ricarica' : 'Reload';

  String get browserHomeTooltip =>
      isItalian ? 'Home' : 'Home';

  String get browserOmniboxHint => isItalian
      ? 'Cerca o inserisci URL (es. pub.dev o flutter riverpod)...'
      : 'Search or enter URL (e.g. pub.dev or flutter riverpod)...';

  String get browserClearTooltip =>
      isItalian ? 'Pulisci' : 'Clear';

  String get removeBookmarkTooltip =>
      isItalian ? 'Rimuovi dai preferiti' : 'Remove bookmark';

  String get addBookmarkTooltip =>
      isItalian ? 'Aggiungi ai preferiti' : 'Add bookmark';

  String get browserGoTooltip =>
      isItalian ? 'Vai' : 'Go';

  String browserSearchEngineTooltip(String engine) =>
      isItalian ? 'Motore di ricerca: $engine' : 'Search engine: $engine';

  String get browserLoadingInProgress =>
      isItalian ? 'Caricamento in corso...' : 'Loading...';

  String get unableToLoadPageTitle =>
      isItalian ? 'Impossibile caricare la pagina' : 'Unable to load page';

  String get retryBtn =>
      isItalian ? 'Riprova' : 'Retry';

  String get openExternallyBtn =>
      isItalian ? 'Apri esternamente' : 'Open externally';

  String get noMainTextDetectedTitle => isItalian
      ? 'Nessun testo principale rilevato'
      : 'No main text detected';

  String get noMainTextDetectedMessage => isItalian
      ? 'Questa pagina potrebbe richiedere JavaScript attivo o un browser completo per visualizzare il contenuto.'
      : 'This page may require JavaScript or a full browser to display content.';

  String get openInSystemBrowserBtn => isItalian
      ? 'Apri nel browser di sistema'
      : 'Open in system browser';

  String browserSearchResultsCount(int count) =>
      isItalian ? 'Risultati ($count):' : 'Results ($count):';

  String browserExtractedCodeCount(int count) => isItalian
      ? 'Codice estratti ($count):'
      : 'Extracted code ($count):';

  String get copyCodeTooltip =>
      isItalian ? 'Copia codice' : 'Copy code';

  String get codeCopiedMessage =>
      isItalian ? 'Codice copiato.' : 'Code copied.';

  String browserPageLinksCount(int count) => isItalian
      ? 'Collegamenti nella pagina ($count):'
      : 'Page links ($count):';

  String get browserHomeSubtitle => isItalian
      ? 'Naviga e cerca documentazione, librerie o soluzioni per il tuo progetto'
      : 'Browse and search documentation, packages, or solutions for your project';

  String browserHomeSearchHint(String engine) =>
      isItalian ? 'Cerca con $engine...' : 'Search with $engine...';

  String get quickBookmarksHeader =>
      isItalian ? 'Segnalibri veloci' : 'Quick bookmarks';

  String get recentSearchesHeader =>
      isItalian ? 'Ricerche recenti' : 'Recent searches';

  // ---------------------------------------------------------------------------
  // Metrics (Nerd Stats)
  // ---------------------------------------------------------------------------
  String get nerdStatsNotAvailable =>
      isItalian ? 'n/d' : 'N/A';
}
