import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

final appStringsProvider = Provider<AppStrings>((ref) {
  final lang = ref.watch(appLanguageProvider);
  return AppStrings(lang);
});
