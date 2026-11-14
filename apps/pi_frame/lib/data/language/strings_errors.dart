import 'language_settings.dart';

/// Localized titles and hints for user-facing error descriptions.
/// See `domain/errors/user_facing_error.dart` for the mapping.
extension ErrorStrings on AppStrings {
  String get errorUnknownTitle =>
      isItalian ? 'Operazione non riuscita' : 'Operation failed';

  String get errorDaemonUnreachableTitle =>
      isItalian ? 'Daemon non raggiungibile' : 'Daemon unreachable';
  String get errorDaemonUnreachableHint => isItalian
      ? 'Verifica che il daemon PiFrame sia in esecuzione, poi riprova.'
      : 'Check that the PiFrame daemon is running, then try again.';

  String get errorTimeoutTitle => isItalian
      ? 'Il daemon non ha risposto in tempo'
      : 'The daemon did not respond in time';
  String get errorTimeoutHint =>
      isItalian ? 'Riprova tra qualche istante.' : 'Try again in a moment.';

  String get errorNetworkTitle =>
      isItalian ? 'Connessione di rete non riuscita' : 'Network connection failed';
  String get errorNetworkHint => isItalian
      ? 'Controlla la connessione e riprova.'
      : 'Check your connection and try again.';

  String get errorPermissionTitle =>
      isItalian ? 'Permesso negato' : 'Permission denied';
  String get errorPermissionHint => isItalian
      ? 'PiFrame non può accedere a questo file o cartella.'
      : 'PiFrame cannot access this file or folder.';

  String get errorNotFoundTitle =>
      isItalian ? 'File o cartella non trovati' : 'File or folder not found';
  String get errorNotFoundHint => isItalian
      ? 'Potrebbero essere stati spostati o eliminati.'
      : 'They may have been moved or deleted.';

  String get errorGitMissingTitle =>
      isItalian ? 'Git non è installato' : 'Git is not installed';
  String get errorGitMissingHint => isItalian
      ? 'Installa Git e assicurati che sia nel PATH, poi riavvia PiFrame.'
      : 'Install Git and make sure it is on the PATH, then restart PiFrame.';

  String get errorNotRepositoryTitle =>
      isItalian ? 'Nessun repository Git' : 'No Git repository';
  String get errorNotRepositoryHint => isItalian
      ? 'Apri una cartella dentro un repository Git.'
      : 'Open a folder inside a Git repository.';

  String get errorSessionMissingTitle =>
      isItalian ? 'Sessione non trovata' : 'Session not found';
  String get errorSessionMissingHint => isItalian
      ? 'Potrebbe essere stata chiusa o eliminata.'
      : 'It may have been closed or deleted.';

  String get errorBusyTitle => isItalian
      ? 'Non disponibile mentre Pi lavora'
      : 'Not available while Pi is working';
  String get errorBusyHint => isItalian
      ? 'Riprova quando Pi ha terminato.'
      : 'Try again when Pi has finished.';

  String get errorOutdatedDaemonTitle =>
      isItalian ? 'Il daemon non supporta questa operazione' : 'The daemon does not support this operation';

  String get gitStatusLoadFailed => isItalian
      ? 'Impossibile caricare le modifiche Git'
      : 'Could not load Git changes';
  String get filesLoadFailed =>
      isItalian ? 'Impossibile caricare i file' : 'Could not load files';
  String get extensionErrorTitle =>
      isItalian ? 'Risposta non inviata' : 'Response not sent';
}
