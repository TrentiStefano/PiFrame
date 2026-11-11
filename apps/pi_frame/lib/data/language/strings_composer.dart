import 'language_settings.dart';

extension ComposerStrings on AppStrings {
  // --- Section 1: Composer Main & Prompts ---
  String get composerHintDefault => isItalian
      ? 'Cosa vuoi realizzare? Digita / per i comandi.'
      : 'What do you want to build? Type / for commands.';

  String get composerHintStreaming => isItalian
      ? 'Aggiungi istruzioni o prepara il prossimo turno...'
      : 'Add instructions or queue the next turn...';

  String composerInputHint({required bool isStreaming}) =>
      isStreaming ? composerHintStreaming : composerHintDefault;

  String composerEnlargeTooltip(bool enlarged) => enlarged
      ? (isItalian ? 'Riduci area di testo' : 'Collapse text area')
      : (isItalian ? 'Ingrandisci area di testo' : 'Expand text area');

  String composerEnlargeLabel(bool enlarged) => enlarged
      ? (isItalian ? 'Riduci' : 'Collapse')
      : (isItalian ? 'Ingrandisci' : 'Expand');

  String composerUploadingAttachments(int count) => isItalian
      ? (count == 1 ? 'Caricamento allegato…' : 'Caricamento di $count allegati…')
      : (count == 1 ? 'Uploading attachment…' : 'Uploading $count attachments…');

  String get composerUploadInProgress => isItalian
      ? 'Attendi il termine del caricamento degli allegati.'
      : 'Wait for the attachments to finish uploading.';

  String composerUploadFailed(String name, Object error) {
    final text = error.toString();
    if (text.contains('control mode')) {
      return isItalian
          ? 'Impossibile caricare "$name": questo dispositivo è in sola lettura (modalità view).'
          : 'Cannot upload "$name": this device is read-only (view mode).';
    }
    if (text.contains('Too Large') || text.contains('413')) {
      return isItalian
          ? '"$name" supera il limite di 50 MB.'
          : '"$name" is larger than the 50 MB limit.';
    }
    return isItalian
        ? 'Caricamento di "$name" non riuscito: $text'
        : 'Upload of "$name" failed: $text';
  }

  String get composerChangeModelTooltip =>
      isItalian ? 'Cambia modello' : 'Change model';

  String get composerModelDefaultLabel =>
      isItalian ? 'Modello' : 'Model';

  String get composerThinkingLevelTooltip =>
      isItalian ? 'Livello thinking' : 'Thinking level';

  String get composerVariablePricingContextTooltip => isItalian
      ? 'Dimensione contesto (pricing variabile)'
      : 'Context size (variable pricing)';

  String get composerStopEscTooltip =>
      isItalian ? 'Interrompi (Esc)' : 'Stop (Esc)';

  String get composerFollowUpTooltip =>
      isItalian ? 'Follow-up: metti in coda' : 'Follow-up: queue turn';

  String composerReviewChangesTooltip(bool reviewing) => reviewing
      ? (isItalian ? 'Chiudi revisione modifiche' : 'Close review changes')
      : (isItalian ? 'Rivedi modifiche ai file' : 'Review file changes');

  String get composerSendLabel => isItalian ? 'Invia' : 'Send';

  String get composerAgentAnsweringMinimized => isItalian
      ? 'L\'agente sta rispondendo... Passa il mouse o clicca per scrivere'
      : 'Agent is responding... Hover or click to type';

  String get composerStopAction => isItalian ? 'Interrompi' : 'Stop';

  // --- Section 2: Composer Steer & Queue ---
  String steerEditDialogTitle(int index) => isItalian
      ? 'Modifica messaggio in coda (Steer #${index + 1})'
      : 'Edit queued message (Steer #${index + 1})';

  String get steerEditDialogDesc => isItalian
      ? 'Modifica il testo del messaggio in coda prima che venga inviato all\'agente:'
      : 'Edit queued message text before it is sent to the agent:';

  String get steerLoadedToComposer => isItalian
      ? 'Messaggio caricato nel composer per la modifica'
      : 'Message loaded into composer for editing';

  String get steerLoadToComposerAction =>
      isItalian ? 'Carica nel composer' : 'Load into composer';

  String get steerUpdateAction => isItalian ? 'Aggiorna' : 'Update';

  String composerQueuedSummary(int total, int steer, int followUp) => isItalian
      ? 'In coda ($total): $steer steer, $followUp follow-up'
      : 'Queued ($total): $steer steer, $followUp follow-up';

  String composerToggleQueueTooltip(bool expanded) => expanded
      ? (isItalian ? 'Nascondi messaggi in coda' : 'Hide queued messages')
      : (isItalian ? 'Mostra messaggi in coda' : 'Show queued messages');

  String get composerClearQueueAction =>
      isItalian ? 'Svuota coda' : 'Clear queue';

  String get composerEditSteerTooltip => isItalian
      ? 'Modifica messaggio steer in coda'
      : 'Edit queued steer message';

  String get composerDeleteFromQueueTooltip =>
      isItalian ? 'Elimina dalla coda' : 'Delete from queue';

  // --- Section 3: Composer Errors, Recovery & Dialogs ---
  String get composerWorkerCrashBanner => isItalian
      ? 'Il worker Pi è terminato inaspettatamente. Nessun comando è stato re-inviato automaticamente.'
      : 'Pi worker terminated unexpectedly. No command was resent automatically.';

  String get composerRecoverSessionAction =>
      isItalian ? 'Riprendi sessione' : 'Resume session';

  String get composerRemoveAttachmentsBeforePiCommand => isItalian
      ? 'Rimuovi gli allegati prima di eseguire un comando Pi.'
      : 'Remove attachments before running a Pi command.';

  String composerCommandSourceLabel(String source) => switch (source) {
        'builtin' => 'Pi',
        'extension' => isItalian ? 'estensione' : 'extension',
        'skill' => 'skill',
        _ => 'prompt',
      };

  String get composerRemoveCommandTooltip =>
      isItalian ? 'Rimuovi comando (Backspace)' : 'Remove command (Backspace)';

  String composerCommandArgsHint(String name, String argumentHint) => isItalian
      ? '${argumentHint.isEmpty ? 'Nessun argomento richiesto' : argumentHint} · Invio esegue /$name'
      : '${argumentHint.isEmpty ? 'No arguments needed' : argumentHint} · Enter runs /$name';

  String composerCommandFailed(Object error) =>
      isItalian ? 'Comando non riuscito: $error' : 'Command failed: $error';

  String composerSendFailed(Object error) =>
      isItalian ? 'Invio non riuscito: $error' : 'Send failed: $error';

  String get composerVerifySessionTitle =>
      isItalian ? 'Verifica la sessione Pi' : 'Verify Pi session';

  String get composerVerifySessionContent => isItalian
      ? 'PiFrame rileva Pi interattivo aperto in questa cartella, ma Pi non comunica quale file di sessione usa. Continua solo se questa sessione non è aperta nel terminale. Due processi sullo stesso file possono danneggiare la cronologia.'
      : 'PiFrame detects interactive Pi running in this folder, but Pi does not report which session file it uses. Continue only if this session is not open in a terminal. Two processes accessing the same file can corrupt history.';

  String get composerContinueHereAction =>
      isItalian ? 'Continua qui' : 'Continue here';

  String composerResumeFailed(Object error) =>
      isItalian ? 'Ripresa non riuscita: $error' : 'Resume failed: $error';

  String composerActionFailed(Object error) =>
      isItalian ? 'Azione non riuscita: $error' : 'Action failed: $error';

  String get composerNoFilesAvailable => isItalian
      ? 'Nessun file disponibile nella sessione.'
      : 'No files available in this session.';

  String get composerImagesFilterLabel =>
      isItalian ? 'Immagini' : 'Images';

  String composerInterruptFailed(Object error) =>
      isItalian ? 'Interruzione non riuscita: $error' : 'Interrupt failed: $error';

  String get composerAgentInterrupted => isItalian
      ? 'Agente interrotto. La coda di messaggi è stata cancellata.'
      : 'Agent interrupted. Queued messages were cleared.';

  String composerModelNotFound(String name) =>
      isItalian ? 'Modello "$name" non trovato.' : 'Model "$name" not found.';

  String get composerModelAmbiguous => isItalian
      ? 'Modello ambiguo. Usa provider/id per sceglierlo.'
      : 'Ambiguous model. Use provider/id to select.';

  String composerThinkingLevelNotAvailable(String lvl) => isItalian
      ? 'Livello di thinking "$lvl" non disponibile.'
      : 'Thinking level "$lvl" not available.';

  String get composerLoginNoArgs => isItalian
      ? '/login non accetta argomenti.'
      : '/login does not take arguments.';

  String get composerLogoutNoArgs => isItalian
      ? '/logout non accetta argomenti.'
      : '/logout does not take arguments.';

  String get composerNoAgentMessageToCopy => isItalian
      ? 'Nessun messaggio dell’agente da copiare.'
      : 'No agent message to copy.';

  String get composerLastAgentMessageCopied => isItalian
      ? 'Ultimo messaggio dell’agente copiato.'
      : 'Last agent message copied.';

  String composerTuiCommandNotice(String name) => isItalian
      ? '/$name è un comando integrato di Pi basato sulla TUI. PiFrame non lo invia al modello, ma non offre ancora questa azione.'
      : '/$name is a Pi built-in TUI command. PiFrame does not forward it to the model, but does not support this action yet.';

  String get composerSessionNameTitle =>
      isItalian ? 'Nome sessione' : 'Session name';

  String get composerCloneNotReturned => isItalian
      ? 'La sessione duplicata non è stata restituita.'
      : 'Cloned session was not returned.';

  String get composerForkNoUserMessages => isItalian
      ? 'La sessione non contiene messaggi utente da cui creare un fork.'
      : 'Session does not contain user messages to fork from.';

  String get composerForkTitle =>
      isItalian ? 'Crea un fork' : 'Create fork';

  String get composerForkNotCreated =>
      isItalian ? 'Il fork non è stato creato.' : 'Fork was not created.';

  String get composerResumeTitle =>
      isItalian ? 'Riprendi una sessione' : 'Resume session';

  String get composerNoSessionsAvailable =>
      isItalian ? 'Nessuna sessione disponibile.' : 'No sessions available.';

  String get composerPiSessionTitle =>
      isItalian ? 'Sessione Pi' : 'Pi Session';

  String composerSessionInfoName(String name) =>
      isItalian ? 'Nome: $name' : 'Name: $name';

  String composerSessionInfoSession(String id) =>
      isItalian ? 'Sessione: $id' : 'Session: $id';

  String composerSessionInfoFolder(String cwd) =>
      isItalian ? 'Cartella: $cwd' : 'Folder: $cwd';

  String composerSessionInfoModel(String model) =>
      isItalian ? 'Modello: $model' : 'Model: $model';

  String composerSessionInfoThinking(String thinking) =>
      isItalian ? 'Thinking: $thinking' : 'Thinking: $thinking';

  String get composerNoAlternativeModels => isItalian
      ? 'Nessun modello alternativo disponibile.'
      : 'No alternative models available.';

  String get composerModelContextNotAvailableDaemon => isItalian
      ? 'Contesto del modello non disponibile. Riprova quando il daemon è connesso.'
      : 'Model context not available. Try again once daemon connects.';

  String get composerContextSizeTitle =>
      isItalian ? 'Dimensione Contesto' : 'Context size';

  String composerContextSelectionFailed(Object error) => isItalian
      ? 'Selezione contesto non riuscita: $error'
      : 'Context selection failed: $error';

  String get composerAttachTooltip => isItalian
      ? 'Allega file, link o immagine'
      : 'Attach file, link, or image';

  String get composerAttachFromRepo =>
      isItalian ? 'File dal repository' : 'File from repository';

  String get composerAttachExternalFile =>
      isItalian ? 'File esterno' : 'External file';

  String get composerAttachWebLink =>
      isItalian ? 'Link web' : 'Web link';

  String get composerAttachImage =>
      isItalian ? 'Immagine' : 'Image';

  String get composerReadOnlyTerminalNotice => isItalian
      ? 'Pi ha una sessione interattiva aperta in questa cartella. Duplica per evitare scritture concorrenti.'
      : 'Pi has an interactive session open in this folder. Duplicate to avoid concurrent writes.';

  String get composerReadOnlyUnknownNotice => isItalian
      ? 'PiFrame non può verificare che questa sessione sia chiusa. Duplica per continuare in sicurezza.'
      : 'PiFrame cannot verify if this session is closed. Duplicate to continue safely.';

  String get composerCloneAndContinueAction =>
      isItalian ? 'Duplica e continua' : 'Duplicate and continue';

  String composerDuplicationFailed(Object error) => isItalian
      ? 'Duplicazione non riuscita: $error'
      : 'Duplication failed: $error';

  String get composerDaemonNotConnected =>
      isItalian ? 'Daemon non connesso' : 'Daemon not connected';

  // --- Section 4: Attachments & Dialogs ---
  String get attEnterValidUrl =>
      isItalian ? 'Inserisci un URL valido' : 'Enter a valid URL';

  String get attInvalidUrlFormat =>
      isItalian ? 'Formato URL non valido' : 'Invalid URL format';

  String get attAddWebLinkTitle =>
      isItalian ? 'Aggiungi Link Web' : 'Add Web Link';

  String get attTitleOptional => isItalian
      ? 'Titolo o etichetta (opzionale)'
      : 'Title or label (optional)';

  String get attTitleHint => isItalian
      ? 'Documentazione API, PR GitHub...'
      : 'API documentation, GitHub PR...';

  String get attAddLinkAction =>
      isItalian ? 'Aggiungi Link' : 'Add Link';

  String get attClosePreviewTooltip =>
      isItalian ? 'Chiudi anteprima' : 'Close preview';

  String get attImageLoadError => isItalian
      ? 'Impossibile caricare l\'immagine'
      : 'Unable to load image';

  String attClickToExpand(String name) => isItalian
      ? '$name (Clicca per ingrandire)'
      : '$name (Click to expand)';

  // --- Section 5: Copilot File Picker & Mentions ---
  String get copilotAddContextTitle =>
      isItalian ? 'Aggiungi contesto al chat' : 'Add context to chat';

  String get copilotAddContextSubtitle => isItalian
      ? 'Cerca file per includere il contenuto o collegarlo con @'
      : 'Search files to include content or link with @';

  String get copilotCloseEscTooltip =>
      isItalian ? 'Chiudi (Esc)' : 'Close (Esc)';

  String get copilotSearchHint => isItalian
      ? 'Cerca per nome file o percorso...'
      : 'Search by filename or path...';

  String copilotFilesFound(int n) => isItalian
      ? '$n file trovati'
      : (n == 1 ? '1 file found' : '$n files found');

  String get copilotKeyNavHint => isItalian
      ? '↑↓ seleziona · Invio conferma'
      : '↑↓ select · Enter confirm';

  String get copilotNoFilesMatch => isItalian
      ? 'Nessun file corrisponde alla ricerca'
      : 'No files match search';

  String copilotLoadingMore(int cur, int total) => isItalian
      ? 'Caricamento altri file ($cur/$total)...'
      : 'Loading more files ($cur/$total)...';

  String get copilotLinkAtAction =>
      isItalian ? 'Collega @' : 'Link @';

  String get mentionLinkFileHeader =>
      isItalian ? 'Collega file (@)' : 'Link file (@)';

  String get mentionTabEnterComplete => isItalian
      ? 'Tab / Invio per completare'
      : 'Tab / Enter to complete';

  // --- Section 6: Context Panel & Context Window Selector ---
  String get workspaceHeader =>
      isItalian ? 'Area di lavoro' : 'Workspace';

  String get sessionHeader =>
      isItalian ? 'Sessione' : 'Session';

  String get modelHeader =>
      isItalian ? 'Modello LLM' : 'Model';

  String get noModelEnabled => isItalian
      ? 'Nessun modello abilitato in Pi.'
      : 'No model enabled in Pi.';

  String modelListNotAvailable(String current) => isItalian
      ? '$current\nElenco modelli non disponibile.'
      : '$current\nModel list not available.';

  String get thinkingLevelHeader =>
      isItalian ? 'Livello Thinking' : 'Thinking level';

  String get contextSizeHeader =>
      isItalian ? 'Dimensione Contesto' : 'Context size';

  String get compactionMarginHeader => isItalian
      ? 'Margine per compattazione (%)'
      : 'Compaction margin (%)';

  String get compactionMarginStep =>
      isItalian ? '0,5–25% · Passo 0,5%' : '0.5–25% · Step 0.5%';

  String compactionMarginOutOfRange(String percent) => isItalian
      ? 'Margine salvato fuori intervallo: $percent%. Trascina per aggiornarlo.'
      : 'Saved margin out of range: $percent%. Drag to update.';

  String get autoCompactionDisabled => isItalian
      ? 'Compattazione automatica disabilitata in Pi.'
      : 'Automatic compaction disabled in Pi.';

  String compactionThresholdInfo(String threshold, String percent) => isItalian
      ? 'Soglia: $threshold token; margine $percent%. Pi può compattare prima se la sua riserva nativa è maggiore. Output singoli possono oltrepassare la soglia.'
      : 'Threshold: $threshold tokens; margin $percent%. Pi may compact sooner if its native reserve is higher. Single outputs may exceed the threshold.';

  String get compactionMarginUnused => isItalian
      ? 'Il margine resta inutilizzato prima della compattazione automatica.'
      : 'Margin is unused until automatic compaction.';

  String get contextUsageHeader =>
      isItalian ? 'Utilizzo Contesto' : 'Context usage';

  String get dataNotAvailable =>
      isItalian ? 'Dati non disponibili' : 'Data not available';

  String contextTokensUsage(int tokens, String window) =>
      isItalian ? '$tokens / $window token' : '$tokens / $window tokens';

  String get compactingLabel =>
      isItalian ? 'Compattazione...' : 'Compacting...';

  String get compactContextAction =>
      isItalian ? 'Compatta contesto' : 'Compact context';

  String get duplicateBranchAction =>
      isItalian ? 'Duplica Ramo (Clone)' : 'Duplicate branch (clone)';

  String get branchTreeAction =>
      isItalian ? 'Albero dei Rami (Tree)' : 'Branch tree';

  String get compactionCompletedTitle =>
      isItalian ? 'Compattazione completata' : 'Compaction completed';

  String compactionDialogContent(dynamic before, dynamic after, String cost) =>
      isItalian
          ? 'Token prima: $before\nToken dopo: $after\n${cost.isNotEmpty ? "Costo: $cost" : ""}'
          : 'Tokens before: $before\nTokens after: $after\n${cost.isNotEmpty ? "Cost: $cost" : ""}';

  String contextLimitNotApplied(Object error) => isItalian
      ? 'Limite non applicato: $error'
      : 'Limit not applied: $error';

  String get contextMaxNotAvailable =>
      isItalian ? 'Massimo non disponibile' : 'Max not available';

  String get contextSelectLimit =>
      isItalian ? 'Seleziona limite' : 'Select limit';

  String get contextMaxWindow =>
      isItalian ? 'Finestra massima di contesto' : 'Max context window';

  String contextTokensExact(String formatted, int exact) => isItalian
      ? '$formatted token ($exact token esatti)'
      : '$formatted tokens ($exact exact tokens)';

  String contextTokensLabel(int count) =>
      isItalian ? '$count token' : '$count tokens';

  String contextStep50k(String maxFormatted) => isItalian
      ? '100k–$maxFormatted · Passo 50k'
      : '100k–$maxFormatted · Step 50k';

  String compactionMarginNotApplied(Object error) => isItalian
      ? 'Margine non applicato: $error'
      : 'Margin not applied: $error';

  String compactionFailed(Object error) => isItalian
      ? 'Compattazione non riuscita: $error'
      : 'Compaction failed: $error';

  String actionFailed(Object error) => composerActionFailed(error);

  String duplicationFailed(Object error) => composerDuplicationFailed(error);

  String modelsNotAvailable(Object error) => isItalian
      ? 'Modelli non disponibili: $error'
      : 'Models not available: $error';

  // --- Section 7: Dialogs ---
  String get piInstallTitle => isItalian
      ? 'Installazione Pi Coding Agent'
      : 'Pi Coding Agent Installation';

  String get piInstallSubtitle => isItalian
      ? 'Configurazione automatica iniziale'
      : 'Initial automatic setup';

  String get piInstallNotDetected => isItalian
      ? 'Pi Coding Agent non rilevato'
      : 'Pi Coding Agent not detected';

  String get piInstallDescription => isItalian
      ? 'PiFrame utilizza pi-coding-agent (@earendil-works/pi-coding-agent) per alimentare le sessioni e gli strumenti dell\'agente. Non è stato rilevato alcun comando "pi" nel sistema.'
      : 'PiFrame uses pi-coding-agent (@earendil-works/pi-coding-agent) to power agent sessions and tools. No "pi" command was detected on your system.';

  String get piInstallProceedPrompt => isItalian
      ? 'Vuoi procedere con l\'installazione automatica ufficiale adesso?'
      : 'Do you want to proceed with the official automatic installation now?';

  String get piInstallCommandUnix => isItalian
      ? 'Comando: curl -fsSL https://pi.dev/install.sh | sh\n(installazione ufficiale con configurazione automatica dei prerequisiti)'
      : 'Command: curl -fsSL https://pi.dev/install.sh | sh\n(official install with automatic prerequisite setup)';

  String get piInstallCommandWindows => isItalian
      ? 'Comando: irm https://pi.dev/install.ps1 | iex\n(installazione ufficiale con configurazione automatica dei prerequisiti)'
      : 'Command: irm https://pi.dev/install.ps1 | iex\n(official install with automatic prerequisite setup)';

  String get piInstallInProgress => isItalian
      ? 'Installazione di pi-coding-agent in corso...'
      : 'Installing pi-coding-agent...';

  String get piInstallSuccess => isItalian
      ? 'Installazione completata con successo!'
      : 'Installation completed successfully!';

  String get piInstallFailure => isItalian
      ? 'Installazione non riuscita. Verifica i log sottostanti.'
      : 'Installation failed. Check the logs below.';

  String get piInstallWaitingOutput => isItalian
      ? 'In attesa di output...\n'
      : 'Waiting for output...\n';

  String get piInstallPleaseWait => isItalian
      ? 'Attendere il completamento...'
      : 'Please wait for completion...';

  String get piInstallStart => isItalian ? 'Inizia' : 'Start';

  String get piInstallLater => isItalian ? 'Più tardi' : 'Later';

  String get piInstallNow =>
      isItalian ? 'Installa adesso' : 'Install now';

  String get extUiNoDaemonResponse => isItalian
      ? 'Nessuna risposta dal daemon. Riprova.'
      : 'No response from daemon. Please try again.';

  String get extUiInteractionRequest => isItalian
      ? 'Richiesta di Interazione'
      : 'Interaction Request';

  String get extUiLockedByOther => isItalian
      ? 'Un altro client sta rispondendo a questa richiesta.'
      : 'Another client is responding to this request.';

  String get extUiCustomAnswerHint =>
      isItalian ? 'Scrivi la risposta...' : 'Type your answer...';

  String get extUiEnterTextHint =>
      isItalian ? 'Inserisci testo...' : 'Enter text...';

  String get extUiConfirm => isItalian ? 'Conferma' : 'Confirm';

  String get extUiSend => isItalian ? 'Invia' : 'Send';

  // --- Section 8: Side Panel ---
  String sideSendTooltip({required bool sendWithEnter}) => sendWithEnter
      ? (isItalian ? 'Invia (Invio)' : 'Send (Enter)')
      : (isItalian ? 'Invia (Ctrl+Invio)' : 'Send (Ctrl+Enter)');

  // --- Section 9: Session Tree Dialog ---
  String get sessionTreeDialogTitle =>
      isItalian ? 'Albero della Sessione' : 'Session Tree';

  String sessionTreeSessionLabel(String id) =>
      isItalian ? 'Sessione: $id' : 'Session: $id';

  String get sessionTreeReload =>
      isItalian ? 'Ricarica' : 'Reload';

  String sessionTreeError(String err) =>
      isItalian ? 'Errore: $err' : 'Error: $err';

  String get sessionTreeNoBranches => isItalian
      ? 'Nessun ramo secondario per questa sessione.'
      : 'No branches found for this session.';

  String get sessionTreeAllMessagesMainBranch => isItalian
      ? 'Tutti i messaggi appartengono al ramo principale.'
      : 'All messages belong to the main branch.';

  String get sessionTreeActiveBadge =>
      isItalian ? 'ATTIVO' : 'ACTIVE';
}
