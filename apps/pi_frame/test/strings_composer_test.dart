import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/language/strings_composer.dart';

void main() {
  group('ComposerStrings Extension Tests', () {
    test('provides exact Italian strings for composer and context panel', () {
      const strings = AppStrings(AppLanguage.it);
      expect(strings.isItalian, isTrue);

      // Section 1: Composer hints & tooltips
      expect(
        strings.composerHintDefault,
        'Cosa vuoi realizzare? Digita / per i comandi.',
      );
      expect(
        strings.composerHintStreaming,
        'Aggiungi istruzioni o prepara il prossimo turno...',
      );
      expect(
        strings.composerInputHint(isStreaming: false),
        'Cosa vuoi realizzare? Digita / per i comandi.',
      );
      expect(
        strings.composerInputHint(isStreaming: true),
        'Aggiungi istruzioni o prepara il prossimo turno...',
      );
      expect(strings.composerEnlargeTooltip(true), 'Riduci area di testo');
      expect(strings.composerEnlargeTooltip(false), 'Ingrandisci area di testo');
      expect(strings.composerEnlargeLabel(true), 'Riduci');
      expect(strings.composerEnlargeLabel(false), 'Ingrandisci');
      expect(strings.composerChangeModelTooltip, 'Cambia modello');
      expect(strings.composerModelDefaultLabel, 'Modello');
      expect(strings.composerThinkingLevelTooltip, 'Livello thinking');
      expect(
        strings.composerVariablePricingContextTooltip,
        'Dimensione contesto (pricing variabile)',
      );
      expect(strings.composerStopEscTooltip, 'Interrompi (Esc)');
      expect(strings.composerFollowUpTooltip, 'Follow-up: metti in coda');
      expect(
        strings.composerReviewChangesTooltip(false),
        'Rivedi modifiche ai file',
      );
      expect(
        strings.composerReviewChangesTooltip(true),
        'Chiudi revisione modifiche',
      );
      expect(strings.composerSendLabel, 'Invia');
      expect(
        strings.composerAgentAnsweringMinimized,
        'L\'agente sta rispondendo... Passa il mouse o clicca per scrivere',
      );
      expect(strings.composerStopAction, 'Interrompi');

      // Section 2: Steer & Queue
      expect(
        strings.steerEditDialogTitle(0),
        'Modifica messaggio in coda (Steer #1)',
      );
      expect(
        strings.steerEditDialogDesc,
        'Modifica il testo del messaggio in coda prima che venga inviato all\'agente:',
      );
      expect(
        strings.steerLoadedToComposer,
        'Messaggio caricato nel composer per la modifica',
      );
      expect(strings.steerLoadToComposerAction, 'Carica nel composer');
      expect(strings.steerUpdateAction, 'Aggiorna');
      expect(
        strings.composerQueuedSummary(2, 1, 1),
        'In coda (2): 1 steer, 1 follow-up',
      );
      expect(
        strings.composerToggleQueueTooltip(true),
        'Nascondi messaggi in coda',
      );
      expect(
        strings.composerToggleQueueTooltip(false),
        'Mostra messaggi in coda',
      );
      expect(strings.composerClearQueueAction, 'Svuota coda');
      expect(
        strings.composerEditSteerTooltip,
        'Modifica messaggio steer in coda',
      );
      expect(strings.composerDeleteFromQueueTooltip, 'Elimina dalla coda');

      // Section 3: Composer Errors & Dialogs
      expect(
        strings.composerWorkerCrashBanner,
        'Il worker Pi è terminato inaspettatamente. Nessun comando è stato re-inviato automaticamente.',
      );
      expect(strings.composerRecoverSessionAction, 'Riprendi sessione');
      expect(
        strings.composerRemoveAttachmentsBeforePiCommand,
        'Rimuovi gli allegati prima di eseguire un comando Pi.',
      );
      expect(
        strings.composerCommandFailed('err'),
        'Comando non riuscito: err',
      );
      expect(strings.composerSendFailed('err'), 'Invio non riuscito: err');
      expect(strings.composerVerifySessionTitle, 'Verifica la sessione Pi');
      expect(
        strings.composerVerifySessionContent,
        'PiFrame rileva Pi interattivo aperto in questa cartella, ma Pi non comunica quale file di sessione usa. Continua solo se questa sessione non è aperta nel terminale. Due processi sullo stesso file possono danneggiare la cronologia.',
      );
      expect(strings.composerContinueHereAction, 'Continua qui');
      expect(strings.composerResumeFailed('err'), 'Ripresa non riuscita: err');
      expect(strings.composerActionFailed('err'), 'Azione non riuscita: err');
      expect(
        strings.composerNoFilesAvailable,
        'Nessun file disponibile nella sessione.',
      );
      expect(strings.composerImagesFilterLabel, 'Immagini');
      expect(
        strings.composerInterruptFailed('err'),
        'Interruzione non riuscita: err',
      );
      expect(
        strings.composerAgentInterrupted,
        'Agente interrotto. La coda di messaggi è stata cancellata.',
      );
      expect(strings.composerModelNotFound('m'), 'Modello "m" non trovato.');
      expect(
        strings.composerModelAmbiguous,
        'Modello ambiguo. Usa provider/id per sceglierlo.',
      );
      expect(
        strings.composerThinkingLevelNotAvailable('x'),
        'Livello di thinking "x" non disponibile.',
      );
      expect(strings.composerLoginNoArgs, '/login non accetta argomenti.');
      expect(strings.composerLogoutNoArgs, '/logout non accetta argomenti.');
      expect(
        strings.composerNoAgentMessageToCopy,
        'Nessun messaggio dell’agente da copiare.',
      );
      expect(
        strings.composerLastAgentMessageCopied,
        'Ultimo messaggio dell’agente copiato.',
      );
      expect(
        strings.composerTuiCommandNotice('cmd'),
        '/cmd è un comando integrato di Pi basato sulla TUI. PiFrame non lo invia al modello, ma non offre ancora questa azione.',
      );
      expect(strings.composerSessionNameTitle, 'Nome sessione');
      expect(
        strings.composerCloneNotReturned,
        'La sessione duplicata non è stata restituita.',
      );
      expect(
        strings.composerForkNoUserMessages,
        'La sessione non contiene messaggi utente da cui creare un fork.',
      );
      expect(strings.composerForkTitle, 'Crea un fork');
      expect(strings.composerForkNotCreated, 'Il fork non è stato creato.');
      expect(strings.composerResumeTitle, 'Riprendi una sessione');
      expect(
        strings.composerNoSessionsAvailable,
        'Nessuna sessione disponibile.',
      );
      expect(strings.composerPiSessionTitle, 'Sessione Pi');
      expect(strings.composerSessionInfoName('test'), 'Nome: test');
      expect(strings.composerSessionInfoSession('s1'), 'Sessione: s1');
      expect(strings.composerSessionInfoFolder('/dir'), 'Cartella: /dir');
      expect(strings.composerSessionInfoModel('gpt'), 'Modello: gpt');
      expect(strings.composerSessionInfoThinking('med'), 'Thinking: med');
      expect(
        strings.composerNoAlternativeModels,
        'Nessun modello alternativo disponibile.',
      );
      expect(
        strings.composerModelContextNotAvailableDaemon,
        'Contesto del modello non disponibile. Riprova quando il daemon è connesso.',
      );
      expect(strings.composerContextSizeTitle, 'Dimensione Contesto');
      expect(
        strings.composerContextSelectionFailed('err'),
        'Selezione contesto non riuscita: err',
      );
      expect(
        strings.composerAttachTooltip,
        'Allega file, link o immagine',
      );
      expect(strings.composerAttachFromRepo, 'File dal repository');
      expect(strings.composerAttachExternalFile, 'File esterno');
      expect(strings.composerAttachWebLink, 'Link web');
      expect(strings.composerAttachImage, 'Immagine');
      expect(
        strings.composerReadOnlyTerminalNotice,
        'Pi ha una sessione interattiva aperta in questa cartella. Duplica per evitare scritture concorrenti.',
      );
      expect(
        strings.composerReadOnlyUnknownNotice,
        'PiFrame non può verificare che questa sessione sia chiusa. Duplica per continuare in sicurezza.',
      );
      expect(strings.composerCloneAndContinueAction, 'Duplica e continua');
      expect(
        strings.composerDuplicationFailed('err'),
        'Duplicazione non riuscita: err',
      );
      expect(strings.composerDaemonNotConnected, 'Daemon non connesso');

      // Section 4: Attachments
      expect(strings.attEnterValidUrl, 'Inserisci un URL valido');
      expect(strings.attInvalidUrlFormat, 'Formato URL non valido');
      expect(strings.attAddWebLinkTitle, 'Aggiungi Link Web');
      expect(strings.attTitleOptional, 'Titolo o etichetta (opzionale)');
      expect(
        strings.attTitleHint,
        'Documentazione API, PR GitHub...',
      );
      expect(strings.attAddLinkAction, 'Aggiungi Link');
      expect(strings.attClosePreviewTooltip, 'Chiudi anteprima');
      expect(
        strings.attImageLoadError,
        'Impossibile caricare l\'immagine',
      );
      expect(
        strings.attClickToExpand('file.png'),
        'file.png (Clicca per ingrandire)',
      );

      // Section 5: Copilot File Picker & Mentions
      expect(strings.copilotAddContextTitle, 'Aggiungi contesto al chat');
      expect(
        strings.copilotAddContextSubtitle,
        'Cerca file per includere il contenuto o collegarlo con @',
      );
      expect(strings.copilotCloseEscTooltip, 'Chiudi (Esc)');
      expect(
        strings.copilotSearchHint,
        'Cerca per nome file o percorso...',
      );
      expect(strings.copilotFilesFound(3), '3 file trovati');
      expect(strings.copilotKeyNavHint, '↑↓ seleziona · Invio conferma');
      expect(
        strings.copilotNoFilesMatch,
        'Nessun file corrisponde alla ricerca',
      );
      expect(
        strings.copilotLoadingMore(50, 100),
        'Caricamento altri file (50/100)...',
      );
      expect(strings.copilotLinkAtAction, 'Collega @');
      expect(strings.mentionLinkFileHeader, 'Collega file (@)');
      expect(strings.mentionTabEnterComplete, 'Tab / Invio per completare');

      // Section 6: Context panel & Context Window Selector
      expect(strings.workspaceHeader, 'Area di lavoro');
      expect(strings.sessionHeader, 'Sessione');
      expect(strings.modelHeader, 'Modello LLM');
      expect(strings.noModelEnabled, 'Nessun modello abilitato in Pi.');
      expect(
        strings.modelListNotAvailable('gpt'),
        'gpt\nElenco modelli non disponibile.',
      );
      expect(strings.thinkingLevelHeader, 'Livello Thinking');
      expect(strings.contextSizeHeader, 'Dimensione Contesto');
      expect(
        strings.compactionMarginHeader,
        'Margine per compattazione (%)',
      );
      expect(strings.compactionMarginStep, '0,5–25% · Passo 0,5%');
      expect(
        strings.compactionMarginOutOfRange('50.0'),
        'Margine salvato fuori intervallo: 50.0%. Trascina per aggiornarlo.',
      );
      expect(
        strings.autoCompactionDisabled,
        'Compattazione automatica disabilitata in Pi.',
      );
      expect(
        strings.compactionThresholdInfo('100k', '10.0'),
        'Soglia: 100k token; margine 10.0%. Pi può compattare prima se la sua riserva nativa è maggiore. Output singoli possono oltrepassare la soglia.',
      );
      expect(
        strings.compactionMarginUnused,
        'Il margine resta inutilizzato prima della compattazione automatica.',
      );
      expect(strings.contextUsageHeader, 'Utilizzo Contesto');
      expect(strings.dataNotAvailable, 'Dati non disponibili');
      expect(strings.contextTokensUsage(70000, '1M'), '70000 / 1M token');
      expect(strings.compactingLabel, 'Compattazione...');
      expect(strings.compactContextAction, 'Compatta contesto');
      expect(strings.duplicateBranchAction, 'Duplica Ramo (Clone)');
      expect(strings.branchTreeAction, 'Albero dei Rami (Tree)');
      expect(strings.compactionCompletedTitle, 'Compattazione completata');
      expect(
        strings.compactionDialogContent(100, 50, '\$0.01'),
        'Token prima: 100\nToken dopo: 50\nCosto: \$0.01',
      );
      expect(
        strings.contextLimitNotApplied('err'),
        'Limite non applicato: err',
      );
      expect(strings.contextMaxNotAvailable, 'Massimo non disponibile');
      expect(strings.contextSelectLimit, 'Seleziona limite');
      expect(strings.contextMaxWindow, 'Finestra massima di contesto');
      expect(
        strings.contextTokensExact('250k', 250000),
        '250k token (250000 token esatti)',
      );
      expect(strings.contextTokensLabel(250000), '250000 token');
      expect(strings.contextStep50k('1M'), '100k–1M · Passo 50k');
      expect(
        strings.compactionMarginNotApplied('err'),
        'Margine non applicato: err',
      );
      expect(
        strings.compactionFailed('err'),
        'Compattazione non riuscita: err',
      );
      expect(strings.modelsNotAvailable('err'), 'Modelli non disponibili: err');

      // Section 7: Dialogs
      expect(strings.piInstallTitle, 'Installazione Pi Coding Agent');
      expect(
        strings.piInstallSubtitle,
        'Configurazione automatica iniziale',
      );
      expect(strings.piInstallNotDetected, 'Pi Coding Agent non rilevato');
      expect(
        strings.piInstallDescription,
        'PiFrame utilizza pi-coding-agent (@earendil-works/pi-coding-agent) per alimentare le sessioni e gli strumenti dell\'agente. Non è stato rilevato alcun comando "pi" nel sistema.',
      );
      expect(
        strings.piInstallProceedPrompt,
        'Vuoi procedere con l\'installazione automatica ufficiale adesso?',
      );
      expect(
        strings.piInstallCommandUnix,
        'Comando: curl -fsSL https://pi.dev/install.sh | sh\n(installazione ufficiale con configurazione automatica dei prerequisiti)',
      );
      expect(
        strings.piInstallCommandWindows,
        'Comando: irm https://pi.dev/install.ps1 | iex\n(installazione ufficiale con configurazione automatica dei prerequisiti)',
      );
      expect(
        strings.piInstallInProgress,
        'Installazione di pi-coding-agent in corso...',
      );
      expect(
        strings.piInstallSuccess,
        'Installazione completata con successo!',
      );
      expect(
        strings.piInstallFailure,
        'Installazione non riuscita. Verifica i log sottostanti.',
      );
      expect(strings.piInstallWaitingOutput, 'In attesa di output...\n');
      expect(strings.piInstallPleaseWait, 'Attendere il completamento...');
      expect(strings.piInstallStart, 'Inizia');
      expect(strings.piInstallLater, 'Più tardi');
      expect(strings.piInstallNow, 'Installa adesso');
      expect(
        strings.extUiNoDaemonResponse,
        'Nessuna risposta dal daemon. Riprova.',
      );
      expect(strings.extUiInteractionRequest, 'Richiesta di Interazione');
      expect(
        strings.extUiLockedByOther,
        'Un altro client sta rispondendo a questa richiesta.',
      );
      expect(strings.extUiCustomAnswerHint, 'Scrivi la risposta...');
      expect(strings.extUiEnterTextHint, 'Inserisci testo...');
      expect(strings.extUiConfirm, 'Conferma');
      expect(strings.extUiSend, 'Invia');

      // Section 8: Side Panel
      expect(
        strings.sideSendTooltip(sendWithEnter: true),
        'Invia (Invio)',
      );
      expect(
        strings.sideSendTooltip(sendWithEnter: false),
        'Invia (Ctrl+Invio)',
      );

      // Section 9: Session Tree Dialog
      expect(strings.sessionTreeDialogTitle, 'Albero della Sessione');
      expect(strings.sessionTreeSessionLabel('s1'), 'Sessione: s1');
      expect(strings.sessionTreeReload, 'Ricarica');
      expect(strings.sessionTreeError('err'), 'Errore: err');
      expect(
        strings.sessionTreeNoBranches,
        'Nessun ramo secondario per questa sessione.',
      );
      expect(
        strings.sessionTreeAllMessagesMainBranch,
        'Tutti i messaggi appartengono al ramo principale.',
      );
      expect(strings.sessionTreeActiveBadge, 'ATTIVO');
    });

    test('provides natural, concise English translations', () {
      const strings = AppStrings(AppLanguage.en);
      expect(strings.isItalian, isFalse);

      // Section 1: Composer hints & tooltips
      expect(
        strings.composerHintDefault,
        'What do you want to build? Type / for commands.',
      );
      expect(
        strings.composerHintStreaming,
        'Add instructions or queue the next turn...',
      );
      expect(
        strings.composerInputHint(isStreaming: false),
        'What do you want to build? Type / for commands.',
      );
      expect(
        strings.composerInputHint(isStreaming: true),
        'Add instructions or queue the next turn...',
      );
      expect(strings.composerEnlargeTooltip(true), 'Collapse text area');
      expect(strings.composerEnlargeTooltip(false), 'Expand text area');
      expect(strings.composerEnlargeLabel(true), 'Collapse');
      expect(strings.composerEnlargeLabel(false), 'Expand');
      expect(strings.composerChangeModelTooltip, 'Change model');
      expect(strings.composerModelDefaultLabel, 'Model');
      expect(strings.composerThinkingLevelTooltip, 'Thinking level');
      expect(
        strings.composerVariablePricingContextTooltip,
        'Context size (variable pricing)',
      );
      expect(strings.composerStopEscTooltip, 'Stop (Esc)');
      expect(strings.composerFollowUpTooltip, 'Follow-up: queue turn');
      expect(
        strings.composerReviewChangesTooltip(false),
        'Review file changes',
      );
      expect(
        strings.composerReviewChangesTooltip(true),
        'Close review changes',
      );
      expect(strings.composerSendLabel, 'Send');
      expect(
        strings.composerAgentAnsweringMinimized,
        'Agent is responding... Hover or click to type',
      );
      expect(strings.composerStopAction, 'Stop');

      // Section 2: Steer & Queue
      expect(
        strings.steerEditDialogTitle(0),
        'Edit queued message (Steer #1)',
      );
      expect(
        strings.steerEditDialogDesc,
        'Edit queued message text before it is sent to the agent:',
      );
      expect(
        strings.steerLoadedToComposer,
        'Message loaded into composer for editing',
      );
      expect(strings.steerLoadToComposerAction, 'Load into composer');
      expect(strings.steerUpdateAction, 'Update');
      expect(
        strings.composerQueuedSummary(2, 1, 1),
        'Queued (2): 1 steer, 1 follow-up',
      );
      expect(
        strings.composerToggleQueueTooltip(true),
        'Hide queued messages',
      );
      expect(
        strings.composerToggleQueueTooltip(false),
        'Show queued messages',
      );
      expect(strings.composerClearQueueAction, 'Clear queue');
      expect(
        strings.composerEditSteerTooltip,
        'Edit queued steer message',
      );
      expect(strings.composerDeleteFromQueueTooltip, 'Delete from queue');

      // Section 3: Composer Errors & Dialogs
      expect(
        strings.composerWorkerCrashBanner,
        'Pi worker terminated unexpectedly. No command was resent automatically.',
      );
      expect(strings.composerRecoverSessionAction, 'Resume session');
      expect(
        strings.composerRemoveAttachmentsBeforePiCommand,
        'Remove attachments before running a Pi command.',
      );
      expect(
        strings.composerCommandFailed('err'),
        'Command failed: err',
      );
      expect(strings.composerSendFailed('err'), 'Send failed: err');
      expect(strings.composerVerifySessionTitle, 'Verify Pi session');
      expect(
        strings.composerVerifySessionContent,
        'PiFrame detects interactive Pi running in this folder, but Pi does not report which session file it uses. Continue only if this session is not open in a terminal. Two processes accessing the same file can corrupt history.',
      );
      expect(strings.composerContinueHereAction, 'Continue here');
      expect(strings.composerResumeFailed('err'), 'Resume failed: err');
      expect(strings.composerActionFailed('err'), 'Action failed: err');
      expect(
        strings.composerNoFilesAvailable,
        'No files available in this session.',
      );
      expect(strings.composerImagesFilterLabel, 'Images');
      expect(
        strings.composerInterruptFailed('err'),
        'Interrupt failed: err',
      );
      expect(
        strings.composerAgentInterrupted,
        'Agent interrupted. Queued messages were cleared.',
      );
      expect(strings.composerModelNotFound('m'), 'Model "m" not found.');
      expect(
        strings.composerModelAmbiguous,
        'Ambiguous model. Use provider/id to select.',
      );
      expect(
        strings.composerThinkingLevelNotAvailable('x'),
        'Thinking level "x" not available.',
      );
      expect(strings.composerLoginNoArgs, '/login does not take arguments.');
      expect(strings.composerLogoutNoArgs, '/logout does not take arguments.');
      expect(
        strings.composerNoAgentMessageToCopy,
        'No agent message to copy.',
      );
      expect(
        strings.composerLastAgentMessageCopied,
        'Last agent message copied.',
      );
      expect(
        strings.composerTuiCommandNotice('cmd'),
        '/cmd is a Pi built-in TUI command. PiFrame does not forward it to the model, but does not support this action yet.',
      );
      expect(strings.composerSessionNameTitle, 'Session name');
      expect(
        strings.composerCloneNotReturned,
        'Cloned session was not returned.',
      );
      expect(
        strings.composerForkNoUserMessages,
        'Session does not contain user messages to fork from.',
      );
      expect(strings.composerForkTitle, 'Create fork');
      expect(strings.composerForkNotCreated, 'Fork was not created.');
      expect(strings.composerResumeTitle, 'Resume session');
      expect(
        strings.composerNoSessionsAvailable,
        'No sessions available.',
      );
      expect(strings.composerPiSessionTitle, 'Pi Session');
      expect(strings.composerSessionInfoName('test'), 'Name: test');
      expect(strings.composerSessionInfoSession('s1'), 'Session: s1');
      expect(strings.composerSessionInfoFolder('/dir'), 'Folder: /dir');
      expect(strings.composerSessionInfoModel('gpt'), 'Model: gpt');
      expect(strings.composerSessionInfoThinking('med'), 'Thinking: med');
      expect(
        strings.composerNoAlternativeModels,
        'No alternative models available.',
      );
      expect(
        strings.composerModelContextNotAvailableDaemon,
        'Model context not available. Try again once daemon connects.',
      );
      expect(strings.composerContextSizeTitle, 'Context size');
      expect(
        strings.composerContextSelectionFailed('err'),
        'Context selection failed: err',
      );
      expect(
        strings.composerAttachTooltip,
        'Attach file, link, or image',
      );
      expect(strings.composerAttachFromRepo, 'File from repository');
      expect(strings.composerAttachExternalFile, 'External file');
      expect(strings.composerAttachWebLink, 'Web link');
      expect(strings.composerAttachImage, 'Image');
      expect(
        strings.composerReadOnlyTerminalNotice,
        'Pi has an interactive session open in this folder. Duplicate to avoid concurrent writes.',
      );
      expect(
        strings.composerReadOnlyUnknownNotice,
        'PiFrame cannot verify if this session is closed. Duplicate to continue safely.',
      );
      expect(strings.composerCloneAndContinueAction, 'Duplicate and continue');
      expect(
        strings.composerDuplicationFailed('err'),
        'Duplication failed: err',
      );
      expect(strings.composerDaemonNotConnected, 'Daemon not connected');

      // Section 4: Attachments
      expect(strings.attEnterValidUrl, 'Enter a valid URL');
      expect(strings.attInvalidUrlFormat, 'Invalid URL format');
      expect(strings.attAddWebLinkTitle, 'Add Web Link');
      expect(strings.attTitleOptional, 'Title or label (optional)');
      expect(
        strings.attTitleHint,
        'API documentation, GitHub PR...',
      );
      expect(strings.attAddLinkAction, 'Add Link');
      expect(strings.attClosePreviewTooltip, 'Close preview');
      expect(strings.attImageLoadError, 'Unable to load image');
      expect(
        strings.attClickToExpand('file.png'),
        'file.png (Click to expand)',
      );

      // Section 5: Copilot File Picker & Mentions
      expect(strings.copilotAddContextTitle, 'Add context to chat');
      expect(
        strings.copilotAddContextSubtitle,
        'Search files to include content or link with @',
      );
      expect(strings.copilotCloseEscTooltip, 'Close (Esc)');
      expect(
        strings.copilotSearchHint,
        'Search by filename or path...',
      );
      expect(strings.copilotFilesFound(1), '1 file found');
      expect(strings.copilotFilesFound(3), '3 files found');
      expect(strings.copilotKeyNavHint, '↑↓ select · Enter confirm');
      expect(
        strings.copilotNoFilesMatch,
        'No files match search',
      );
      expect(
        strings.copilotLoadingMore(50, 100),
        'Loading more files (50/100)...',
      );
      expect(strings.copilotLinkAtAction, 'Link @');
      expect(strings.mentionLinkFileHeader, 'Link file (@)');
      expect(strings.mentionTabEnterComplete, 'Tab / Enter to complete');

      // Section 6: Context panel & Context Window Selector
      expect(strings.workspaceHeader, 'Workspace');
      expect(strings.sessionHeader, 'Session');
      expect(strings.modelHeader, 'Model');
      expect(strings.noModelEnabled, 'No model enabled in Pi.');
      expect(
        strings.modelListNotAvailable('gpt'),
        'gpt\nModel list not available.',
      );
      expect(strings.thinkingLevelHeader, 'Thinking level');
      expect(strings.contextSizeHeader, 'Context size');
      expect(
        strings.compactionMarginHeader,
        'Compaction margin (%)',
      );
      expect(strings.compactionMarginStep, '0.5–25% · Step 0.5%');
      expect(
        strings.compactionMarginOutOfRange('50.0'),
        'Saved margin out of range: 50.0%. Drag to update.',
      );
      expect(
        strings.autoCompactionDisabled,
        'Automatic compaction disabled in Pi.',
      );
      expect(
        strings.compactionThresholdInfo('100k', '10.0'),
        'Threshold: 100k tokens; margin 10.0%. Pi may compact sooner if its native reserve is higher. Single outputs may exceed the threshold.',
      );
      expect(
        strings.compactionMarginUnused,
        'Margin is unused until automatic compaction.',
      );
      expect(strings.contextUsageHeader, 'Context usage');
      expect(strings.dataNotAvailable, 'Data not available');
      expect(strings.contextTokensUsage(70000, '1M'), '70000 / 1M tokens');
      expect(strings.compactingLabel, 'Compacting...');
      expect(strings.compactContextAction, 'Compact context');
      expect(strings.duplicateBranchAction, 'Duplicate branch (clone)');
      expect(strings.branchTreeAction, 'Branch tree');
      expect(strings.compactionCompletedTitle, 'Compaction completed');
      expect(
        strings.compactionDialogContent(100, 50, '\$0.01'),
        'Tokens before: 100\nTokens after: 50\nCost: \$0.01',
      );
      expect(
        strings.contextLimitNotApplied('err'),
        'Limit not applied: err',
      );
      expect(strings.contextMaxNotAvailable, 'Max not available');
      expect(strings.contextSelectLimit, 'Select limit');
      expect(strings.contextMaxWindow, 'Max context window');
      expect(
        strings.contextTokensExact('250k', 250000),
        '250k tokens (250000 exact tokens)',
      );
      expect(strings.contextTokensLabel(250000), '250000 tokens');
      expect(strings.contextStep50k('1M'), '100k–1M · Step 50k');
      expect(
        strings.compactionMarginNotApplied('err'),
        'Margin not applied: err',
      );
      expect(
        strings.compactionFailed('err'),
        'Compaction failed: err',
      );
      expect(strings.modelsNotAvailable('err'), 'Models not available: err');

      // Section 7: Dialogs
      expect(strings.piInstallTitle, 'Pi Coding Agent Installation');
      expect(
        strings.piInstallSubtitle,
        'Initial automatic setup',
      );
      expect(strings.piInstallNotDetected, 'Pi Coding Agent not detected');
      expect(
        strings.piInstallDescription,
        'PiFrame uses pi-coding-agent (@earendil-works/pi-coding-agent) to power agent sessions and tools. No "pi" command was detected on your system.',
      );
      expect(
        strings.piInstallProceedPrompt,
        'Do you want to proceed with the official automatic installation now?',
      );
      expect(
        strings.piInstallCommandUnix,
        'Command: curl -fsSL https://pi.dev/install.sh | sh\n(official install with automatic prerequisite setup)',
      );
      expect(
        strings.piInstallCommandWindows,
        'Command: irm https://pi.dev/install.ps1 | iex\n(official install with automatic prerequisite setup)',
      );
      expect(
        strings.piInstallInProgress,
        'Installing pi-coding-agent...',
      );
      expect(
        strings.piInstallSuccess,
        'Installation completed successfully!',
      );
      expect(
        strings.piInstallFailure,
        'Installation failed. Check the logs below.',
      );
      expect(strings.piInstallWaitingOutput, 'Waiting for output...\n');
      expect(strings.piInstallPleaseWait, 'Please wait for completion...');
      expect(strings.piInstallStart, 'Start');
      expect(strings.piInstallLater, 'Later');
      expect(strings.piInstallNow, 'Install now');
      expect(
        strings.extUiNoDaemonResponse,
        'No response from daemon. Please try again.',
      );
      expect(strings.extUiInteractionRequest, 'Interaction Request');
      expect(
        strings.extUiLockedByOther,
        'Another client is responding to this request.',
      );
      expect(strings.extUiCustomAnswerHint, 'Type your answer...');
      expect(strings.extUiEnterTextHint, 'Enter text...');
      expect(strings.extUiConfirm, 'Confirm');
      expect(strings.extUiSend, 'Send');

      // Section 8: Side Panel
      expect(
        strings.sideSendTooltip(sendWithEnter: true),
        'Send (Enter)',
      );
      expect(
        strings.sideSendTooltip(sendWithEnter: false),
        'Send (Ctrl+Enter)',
      );

      // Section 9: Session Tree Dialog
      expect(strings.sessionTreeDialogTitle, 'Session Tree');
      expect(strings.sessionTreeSessionLabel('s1'), 'Session: s1');
      expect(strings.sessionTreeReload, 'Reload');
      expect(strings.sessionTreeError('err'), 'Error: err');
      expect(
        strings.sessionTreeNoBranches,
        'No branches found for this session.',
      );
      expect(
        strings.sessionTreeAllMessagesMainBranch,
        'All messages belong to the main branch.',
      );
      expect(strings.sessionTreeActiveBadge, 'ACTIVE');
    });
  });
}
