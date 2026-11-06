import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session/transcript_grouping.dart';

enum AppLanguage {
  it('it', 'Italiano (IT)', '🇮🇹'),
  en('en', 'English (EN)', '🇬🇧');

  final String code;
  final String label;
  final String flag;

  const AppLanguage(this.code, this.label, this.flag);

  static AppLanguage fromCode(String? code) {
    if (code == null) return AppLanguage.it;
    return AppLanguage.values.firstWhere(
      (lang) => lang.code == code.toLowerCase().trim(),
      orElse: () => AppLanguage.it,
    );
  }
}

class AppLanguageNotifier extends StateNotifier<AppLanguage> {
  AppLanguageNotifier() : super(AppLanguage.it) {
    _load();
  }

  File? _getStorageFile() {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.piframe');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}/language_settings.json');
    } catch (_) {
      return null;
    }
  }

  void _load() {
    final file = _getStorageFile();
    if (file != null && file.existsSync()) {
      try {
        final content = file.readAsStringSync();
        final map = jsonDecode(content) as Map<String, dynamic>;
        state = AppLanguage.fromCode(map['language']?.toString());
      } catch (_) {}
    }
  }

  void _save() {
    final file = _getStorageFile();
    if (file != null) {
      try {
        file.writeAsStringSync(jsonEncode({'language': state.code}));
      } catch (_) {}
    }
  }

  void setLanguage(AppLanguage language) {
    if (state != language) {
      state = language;
      _save();
    }
  }
}

final appLanguageProvider =
    StateNotifierProvider<AppLanguageNotifier, AppLanguage>((ref) {
  return AppLanguageNotifier();
});

class AppStrings {
  final AppLanguage language;

  const AppStrings(this.language);

  bool get isItalian => language == AppLanguage.it;

  // Settings Header & General
  String get settingsTitle => isItalian ? 'Impostazioni PiFrame' : 'PiFrame Settings';
  String get backToChatTooltip => isItalian ? 'Torna alla conversazione' : 'Back to conversation';
  String get cancel => isItalian ? 'Annulla' : 'Cancel';
  String get save => isItalian ? 'Salva' : 'Save';
  String get close => isItalian ? 'Chiudi' : 'Close';

  // Tabs
  String get tabPiCli => 'PI CLI';
  String get tabPackages => isItalian ? 'PACCHETTI' : 'PACKAGES';
  String get tabDaemon => 'DAEMON';
  String get tabAppearance => isItalian ? 'ASPETTO' : 'APPEARANCE';
  String get tabPrivacy => 'PRIVACY';
  String get tabDiagnostics => isItalian ? 'DIAGNOSTICA' : 'DIAGNOSTICS';
  String get tabUpdates => isItalian ? 'AGGIORNAMENTI' : 'UPDATES';
  String get tabTerminal => isItalian ? 'TERMINALE' : 'TERMINAL';
  String get tabRemote => isItalian ? 'ACCESSO REMOTO' : 'REMOTE ACCESS';
  String get tabAgents => isItalian ? 'AGENTI' : 'AGENTS';

  // Appearance tab
  String get appearanceTitle => isItalian ? 'Personalizzazione Tema e UI' : 'Theme & UI Customization';
  String get appearanceSubtitle => isItalian
      ? 'PiFrame supporta temi personalizzati definiti via file JSON in ~/.piframe/themes/.'
      : 'PiFrame supports custom themes defined via JSON files in ~/.piframe/themes/.';
  String get languageSectionTitle => isItalian ? 'Lingua dell\'Applicazione' : 'Application Language';
  String get languageSectionSubtitle => isItalian
      ? 'Seleziona la lingua per l\'interfaccia grafica e i messaggi dell\'applicazione.'
      : 'Select the language for the graphical interface and application messages.';
  String get useSystemTheme => isItalian ? 'Usa tema di sistema' : 'Use system theme';
  String get useSystemThemeSubtitle => isItalian
      ? 'Adatta automaticamente l\'aspetto in base alla modalità chiara o scura del sistema operativo.'
      : 'Automatically match appearance with operating system dark/light mode.';
  String get selectActiveTheme => isItalian ? 'Seleziona Tema Attivo:' : 'Select Active Theme:';
  String get defaultDarkTheme => isItalian ? 'Tema Scuro Predefinito:' : 'Default Dark Theme:';
  String get defaultLightTheme => isItalian ? 'Tema Chiaro Predefinito:' : 'Default Light Theme:';
  String get importThemeBtn => isItalian ? 'Importa tema JSON (VSCode / PiFrame)' : 'Import JSON Theme (VSCode / PiFrame)';
  String get openThemeEditorBtn => isItalian ? 'Editor Temi / Personalizza Tema' : 'Theme Editor / Customize Theme';

  // Theme Editor
  String get themeEditorTitle => isItalian ? 'Editor Temi Personalizzati' : 'Custom Theme Editor';
  String get themeEditorSubtitle => isItalian
      ? 'Crea un nuovo tema a partire da uno esistente, personalizzane i componenti grafici e salvalo con un nome.'
      : 'Create a new theme based on an existing one, customize visual components, and save with a custom name.';
  String get baseThemeLabel => isItalian ? 'Tema di Partenza' : 'Starting Theme';
  String get themeNameLabel => isItalian ? 'Nome Tema' : 'Theme Name';
  String get themeNameHint => isItalian ? 'Es. Mio Tema Scuro' : 'E.g. My Custom Dark';
  String get themeVariantLabel => isItalian ? 'Variante' : 'Variant';
  String get variantDark => isItalian ? 'Scuro (Dark)' : 'Dark';
  String get variantLight => isItalian ? 'Chiaro (Light)' : 'Light';
  String get previewLabel => isItalian ? 'Anteprima Componenti' : 'Component Preview';
  String get saveThemeAction => isItalian ? 'Salva e Applica Tema' : 'Save & Apply Theme';

  // Theme Editor component categories
  String get catSurfaces => isItalian ? 'Superfici & Sfondo' : 'Surfaces & Background';
  String get catAccents => isItalian ? 'Accenti & Focus' : 'Accents & Focus';
  String get catText => isItalian ? 'Tipografia & Testi' : 'Typography & Text';
  String get catAgent => isItalian ? 'Stati Agente' : 'Agent States';
  String get catSyntax => isItalian ? 'Evidenziazione Sintassi' : 'Syntax Highlighting';

  // Startup Update Notification
  String get updateNoticeTitle => isItalian ? 'Aggiornamenti Rilevati' : 'Updates Available';
  String get updateNoticePi => isItalian ? 'Nuova versione di Pi CLI disponibile' : 'New Pi CLI version available';
  String get updateNoticePackages => isItalian ? 'pacchetti con aggiornamenti' : 'packages with updates';
  String get updateNoticeOpenSettings => isItalian ? 'Dettagli / Aggiorna' : 'Details / Update';
  String get updateNoticeDismiss => isItalian ? 'Ignora' : 'Dismiss';

  // Composer settings & shortcuts
  String get composerSectionTitle => 'Composer';
  String get sendWithEnterTitle =>
      isItalian ? 'Invia con Enter' : 'Send with Enter';
  String get sendWithEnterSubtitle => isItalian
      ? 'Quando attivo, premi Invio per inviare e Shift+Invio per una nuova riga. Quando disattivato, usa Ctrl+Invio per inviare e Invio per andare a capo.'
      : 'When enabled, press Enter to send and Shift+Enter for a new line. When disabled, use Ctrl+Enter to send and Enter for a new line.';
  String get composerSendTooltipSendWithEnter =>
      isItalian ? 'Invia prompt (Invio)' : 'Send prompt (Enter)';
  String get composerSendTooltipDefault =>
      isItalian ? 'Invia prompt (Ctrl+Invio)' : 'Send prompt (Ctrl+Enter)';
  String get composerSteerTooltipSendWithEnter =>
      isItalian ? 'Steer: interrompe e applica (Invio)' : 'Steer: interrupt and apply (Enter)';
  String get composerSteerTooltipDefault =>
      isItalian ? 'Steer: interrompe e applica (Ctrl+Invio)' : 'Steer: interrupt and apply (Ctrl+Enter)';

  String composerSendTooltip({required bool sendWithEnter}) =>
      sendWithEnter ? composerSendTooltipSendWithEnter : composerSendTooltipDefault;

  String composerSteerTooltip({required bool sendWithEnter}) =>
      sendWithEnter ? composerSteerTooltipSendWithEnter : composerSteerTooltipDefault;

  // Nerd stats
  String get nerdStatsSectionTitle =>
      isItalian ? 'Statistiche nerd' : 'Nerd stats';
  String get nerdStatsTitle =>
      isItalian ? 'Statistiche nerd' : 'Nerd stats';
  String get nerdStatsSubtitle => isItalian
      ? 'Mostra le statistiche di sistema (CPU, RAM, disco, GPU) e i frame al secondo (FPS) in tempo reale nella barra del titolo.'
      : 'Show real-time system metrics (CPU, RAM, disk, GPU) and frames per second (FPS) in the title bar.';

  // Git branch browser
  String get branchChipTooltip =>
      isItalian ? 'Cambia ramo Git' : 'Switch Git branch';
  String get branchPickerTitle =>
      isItalian ? 'Passa a un altro ramo' : 'Switch branch';
  String get branchPickerSearchHint =>
      isItalian ? 'Cerca ramo...' : 'Search branches...';
  String get branchPickerNoBranches =>
      isItalian ? 'Nessun ramo trovato' : 'No branches found';
  String get branchPickerLoading =>
      isItalian ? 'Caricamento rami...' : 'Loading branches...';
  String get branchPickerError =>
      isItalian ? 'Impossibile caricare i rami' : 'Failed to load branches';
  String get branchPickerRetry =>
      isItalian ? 'Riprova' : 'Retry';
  String get branchPickerCurrentBranch =>
      isItalian ? 'Ramo corrente' : 'Current branch';
  String get workspaceDirtyDialogTitle =>
      isItalian ? 'Modifiche non salvate' : 'Uncommitted Changes';
  String workspaceDirtyDialogMessage(int changedFiles, int untrackedFiles) =>
      isItalian
          ? 'Hai $changedFiles file modificati e $untrackedFiles non tracciati. Il cambio di ramo è bloccato per proteggere le tue modifiche.'
          : 'You have $changedFiles modified and $untrackedFiles untracked files. Switching branch is blocked to protect your changes.';
  String get stashAndSwitchBtn =>
      isItalian ? 'Salva nello stash e cambia' : 'Stash changes and switch';
  String branchSwitched(String branch) =>
      isItalian ? 'Passato al ramo $branch' : 'Switched to $branch';
  String branchSwitchedStashNotice(String stashMessage) =>
      isItalian
          ? 'Le tue modifiche sono state salvate nello stash: $stashMessage'
          : 'Your changes were stashed: $stashMessage';
  String get branchSwitchFailedTitle =>
      isItalian ? 'Cambio di ramo non riuscito' : 'Branch switch failed';
  String stashRetainedSafeNotice(String stashMessage) =>
      isItalian
          ? 'Le tue modifiche sono al sicuro nello stash: $stashMessage'
          : 'Your changes are safe in the stash: $stashMessage';
  String get branchSwitchAgentWorking =>
      isItalian
          ? 'Impossibile cambiare ramo mentre l\'agente sta lavorando'
          : 'Cannot switch branch while the agent is working';
  String get branchNotFound =>
      isItalian ? 'Ramo non trovato' : 'Branch not found';
  String get branchInvalidName =>
      isItalian ? 'Nome del ramo non valido' : 'Invalid branch name';

  // Step Grouping settings & transcript headers
  String get stepGroupingSectionTitle =>
      isItalian ? 'Raggruppamento passaggi' : 'Step grouping';

  String get stepGroupingModeOff =>
      isItalian ? 'Disattivato' : 'Off';
  String get stepGroupingModeOffDescription => isItalian
      ? 'Mostra tutti i messaggi singolarmente nel flusso normale.'
      : 'Show all messages individually in the normal stream.';

  String get stepGroupingModeWithThinking =>
      isItalian ? 'Con ragionamento' : 'With thinking';
  String get stepGroupingModeWithThinkingDescription => isItalian
      ? 'Raggruppa solo i turni che contengono blocchi di ragionamento.'
      : 'Group turns only when thinking blocks are present.';

  String get stepGroupingModeAlways =>
      isItalian ? 'Sempre' : 'Always';
  String get stepGroupingModeAlwaysDescription => isItalian
      ? 'Raggruppa qualsiasi turno con passaggi intermedi o chiamate a strumenti.'
      : 'Group any turn with intermediate steps or tool calls.';

  String stepGroupingModeLabel(StepGroupingMode mode) {
    switch (mode) {
      case StepGroupingMode.off:
        return stepGroupingModeOff;
      case StepGroupingMode.withThinking:
        return stepGroupingModeWithThinking;
      case StepGroupingMode.always:
        return stepGroupingModeAlways;
    }
  }

  String stepGroupingModeDescription(StepGroupingMode mode) {
    switch (mode) {
      case StepGroupingMode.off:
        return stepGroupingModeOffDescription;
      case StepGroupingMode.withThinking:
        return stepGroupingModeWithThinkingDescription;
      case StepGroupingMode.always:
        return stepGroupingModeAlwaysDescription;
    }
  }

  String get stepGroupingAutoCollapseTitle =>
      isItalian ? 'Comprimi automaticamente' : 'Auto-collapse';
  String get stepGroupingAutoCollapseSubtitle => isItalian
      ? 'Comprime automaticamente il gruppo di passaggi al termine dell\'elaborazione.'
      : 'Automatically collapse the step group when the turn finishes.';

  // Step group headers & labels
  String get stepGroupWorking =>
      isItalian ? 'Elaborazione…' : 'Working…';

  String stepGroupCompletedIn(int n, String s) => isItalian
      ? (n == 1
          ? 'Completato 1 passaggio in $s'
          : 'Completati $n passaggi in $s')
      : (n == 1
          ? 'Completed 1 step in $s'
          : 'Completed $n steps in $s');

  String stepGroupCompleted(int n) => isItalian
      ? (n == 1 ? 'Completato 1 passaggio' : 'Completati $n passaggi')
      : (n == 1 ? 'Completed 1 step' : 'Completed $n steps');

  String stepGroupFinished(int n) => isItalian
      ? (n == 1 ? 'Terminato con 1 passaggio' : 'Terminato con $n passaggi')
      : (n == 1 ? 'Finished with 1 step' : 'Finished with $n steps');

  String stepGroupStoppedWithErrors(int n) => isItalian
      ? (n == 1
          ? 'Interrotto con errori dopo 1 passaggio'
          : 'Interrotto con errori dopo $n passaggi')
      : (n == 1
          ? 'Stopped with errors after 1 step'
          : 'Stopped with errors after $n steps');

  String stepGroupStopped(int n) => isItalian
      ? (n == 1 ? 'Interrotto dopo 1 passaggio' : 'Interrotto dopo $n passaggi')
      : (n == 1 ? 'Stopped after 1 step' : 'Stopped after $n steps');

  String get stepGroupSomeStepsFailed => isItalian
      ? 'Alcuni passaggi sono falliti'
      : 'Some steps failed';

  String get stepGroupShowAll =>
      isItalian ? 'Mostra tutti' : 'Show all';
  String get stepGroupShowLess =>
      isItalian ? 'Mostra meno' : 'Show less';
  String stepGroupShowAllSteps(int n) => isItalian
      ? 'Mostra tutti i passaggi ($n)'
      : 'Show all steps ($n)';
  String get stepGroupInput =>
      isItalian ? 'Input' : 'Input';
  String get stepGroupOutput =>
      isItalian ? 'Output' : 'Output';

  // Agents tab
  String get agentsTitle => isItalian
      ? 'Configurazione Agenti e Sottoagenti'
      : 'Agent & Subagent Configuration';
  String get agentsSubtitle => isItalian
      ? 'Gestisci modelli predefiniti, livelli di thinking e quote di contesto per la sessione principale e i sottoagenti.'
      : 'Manage default models, thinking levels, and context limits for primary sessions and subagents.';
  String get agentsGlobalNote => isItalian
      ? 'Nota: le modifiche si applicano a Pi a livello globale (incluse le sessioni da terminale) e alle NUOVE sessioni o esecuzioni di sottoagenti.'
      : 'Note: changes apply to Pi globally (including terminal sessions) and to NEW sessions or subagent runs.';
  String get agentsNoPackagesTitle => isItalian
      ? 'Nessun pacchetto di sottoagenti installato'
      : 'No subagent package installed';
  String get agentsNoPackagesDesc => isItalian
      ? 'Installa un pacchetto di sottoagenti come pi-subagents (nicobailon) o @tintinweb/pi-subagents usando la scheda PACCHETTI o da terminale con "pi install pi-subagents". Consulta il README per maggiori dettagli.'
      : 'Install a subagent package such as pi-subagents (nicobailon) or @tintinweb/pi-subagents using the PACKAGES tab or terminal with "pi install pi-subagents". See the README for details.';
  String get agentsWarningsTitle => isItalian
      ? 'Avvisi di configurazione'
      : 'Configuration warnings';
  String get agentsSessionDefaultsTitle => isItalian
      ? 'Default per nuove sessioni'
      : 'Defaults for new sessions';
  String get agentsSessionDefaultsSubtitle => isItalian
      ? 'Modello e livello di thinking predefiniti per le nuove sessioni primarie di Pi.'
      : 'Default model and thinking level for new primary Pi sessions.';
  String get agentsSubagentDefaultsTitle => isItalian
      ? 'Default sottoagenti'
      : 'Subagent defaults';
  String get agentsSubagentDefaultsSubtitle => isItalian
      ? 'Impostazioni globali ereditate dai sottoagenti in assenza di override specifici.'
      : 'Global defaults inherited by subagents when no specific override is set.';
  String get agentsDefaultModel => isItalian
      ? 'Modello predefinito'
      : 'Default model';
  String get agentsThinkingLevel => isItalian
      ? 'Livello di thinking'
      : 'Thinking level';
  String get agentsFallbackAgent => isItalian
      ? 'Agente di fallback (tintinweb)'
      : 'Fallback agent (tintinweb)';
  String get agentsListTitle => isItalian
      ? 'Elenco Agenti'
      : 'Agents List';
  String get agentsListSubtitle => isItalian
      ? 'Configura modello, thinking e quote di contesto per ciascun agente.'
      : 'Configure model, thinking, and context limit per agent.';
  String get agentsTableHeaderName => isItalian ? 'Agente' : 'Agent';
  String get agentsTableHeaderModel => isItalian ? 'Modello' : 'Model';
  String get agentsTableHeaderThinking => 'Thinking';
  String get agentsTableHeaderContext => isItalian ? 'Contesto' : 'Context';
  String get agentsPackagesLabel => isItalian ? 'Pacchetti:' : 'Packages:';
  String get agentsContextSingleTierTooltip => isItalian
      ? 'Il modello ha un solo livello di contesto'
      : 'Model has a single context tier';
  String get agentsModelUnavailableWarning => isItalian
      ? 'Non disponibile con le credenziali attuali'
      : 'Not available with current credentials';
  String get agentsResetField => isItalian ? 'Reimposta' : 'Reset';
  String get agentsDiscard => isItalian ? 'Annulla' : 'Discard';
  String get agentsSave => isItalian ? 'Salva modifiche' : 'Save changes';
  String get agentsSaving => isItalian ? 'Salvataggio...' : 'Saving...';
  String get agentsSaveSuccess => isItalian
      ? 'Configurazione agenti salvata con successo.'
      : 'Agent configuration saved successfully.';
  String get agentsReadOnlyNotice => isItalian
      ? 'Accesso remoto: la configurazione degli agenti è in sola lettura.'
      : 'Remote access: agent configuration is read-only.';
  String get agentsReload => isItalian ? 'Ricarica' : 'Reload';
  String get agentsNotAvailableShort => isItalian ? 'n/d' : 'N/A';

  // Side Conversation
  String get sideConversationTitle =>
      isItalian ? 'Conversazione laterale' : 'Side conversation';
  String get sideReadOnlyBadge => 'Side · read-only';
  String get sideNotPartOfMain => isItalian
      ? 'Non fa parte della conversazione principale'
      : 'Not part of the main conversation';
  String get sideSlashDescription => isItalian
      ? 'Conversazione laterale in sola lettura'
      : 'Read-only side conversation';
  String get sideInsertIntoComposer =>
      isItalian ? 'Inserisci nel composer' : 'Insert into composer';
  String get sideInsertedIntoComposer =>
      isItalian ? 'Inserito nel composer' : 'Inserted into composer';
  String get sideCloseConfirmTitle =>
      isItalian ? 'Chiudi conversazione laterale' : 'Close side conversation';
  String get sideCloseConfirmContent => isItalian
      ? 'Nessun dato andrà perso nella conversazione principale.'
      : 'Nothing is lost from the main conversation.';
  String get sideClosedNoticeIdle => isItalian
      ? 'Conversazione laterale chiusa per inattività.'
      : 'Side conversation closed due to inactivity.';
  String get sideClosedNoticeParentClosed => isItalian
      ? 'Conversazione laterale chiusa perché la sessione genitore è stata chiusa.'
      : 'Side conversation closed because the parent session was closed.';
  String get sideClosedNoticeError => isItalian
      ? 'Conversazione laterale chiusa a causa di un errore.'
      : 'Side conversation closed due to an error.';
  String get sideClosedNoticeUser =>
      isItalian ? 'Conversazione laterale chiusa.' : 'Side conversation closed.';
  String get sideMiniComposerHint => isItalian
      ? 'Fai una domanda laterale...'
      : 'Ask a side question...';
  String get sideStopTooltip =>
      isItalian ? 'Interrompi risposta' : 'Stop response';
  String get sideCloseTooltip =>
      isItalian ? 'Chiudi conversazione laterale' : 'Close side conversation';
  String get sideToggleActionTitle => isItalian
      ? 'Conversazione laterale (Ctrl+Shift+B)'
      : 'Side conversation (Ctrl+Shift+B)';
  String get sideToggleActionSubtitle => isItalian
      ? 'Apri o chiudi il pannello laterale di sola lettura'
      : 'Open or toggle read-only side conversation panel';
  String get sideOpening => isItalian
      ? 'Apertura conversazione laterale...'
      : 'Opening side conversation...';
}

final appStringsProvider = Provider<AppStrings>((ref) {
  final lang = ref.watch(appLanguageProvider);
  return AppStrings(lang);
});
