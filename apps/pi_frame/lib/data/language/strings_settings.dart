import '../../domain/update/update_models.dart';
import 'language_settings.dart';

extension SettingsStrings on AppStrings {
  // ---------------------------------------------------------------------------
  // Settings View: General & Daemon & Packages
  // ---------------------------------------------------------------------------
  String get daemonRestartSuccess =>
      isItalian ? 'Daemon riavviato con successo' : 'Daemon restarted successfully';
  String get daemonRestartFailed =>
      isItalian ? 'Riavvio daemon non riuscito' : 'Daemon restart failed';
  String daemonRestartError(Object error) =>
      isItalian ? 'Errore durante il riavvio: $error' : 'Error during restart: $error';
  /// Localized label for a daemon connection state (enum name, e.g. "connected").
  String daemonConnectionStateLabel(String state) => switch (state) {
        'disconnected' => isItalian ? 'Non connesso' : 'Disconnected',
        'connecting' => isItalian ? 'Connessione in corso' : 'Connecting',
        'authenticating' => isItalian ? 'Autenticazione in corso' : 'Authenticating',
        'connected' => isItalian ? 'Connesso' : 'Connected',
        'reconnecting' => isItalian ? 'Riconnessione in corso' : 'Reconnecting',
        _ => state,
      };

  String get daemonNotConnected =>
      isItalian ? 'Daemon non connesso' : 'Daemon not connected';

  String get confirmPackageUpdateTitle =>
      isItalian ? 'Aggiornare il pacchetto?' : 'Update package?';
  String confirmPackageUpdateDesc(String source) => isItalian
      ? 'Pi aggiornerà $source usando il package manager installato. Il codice aggiornato verrà caricato al prossimo avvio di Pi.'
      : 'Pi will update $source using the installed package manager. The updated code will load on next Pi startup.';
  String get actionUpdate =>
      isItalian ? 'Aggiorna' : 'Update';
  String get packageUpdatedSuccess =>
      isItalian ? 'Pacchetto aggiornato' : 'Package updated';

  String get confirmPackageRemoveTitle =>
      isItalian ? 'Rimuovere il pacchetto?' : 'Remove package?';
  String confirmPackageRemoveDesc(String source) => isItalian
      ? 'Pi rimuoverà $source dalle impostazioni utente e dalla directory dei pacchetti. Le cronologie delle sessioni non vengono modificate.'
      : 'Pi will remove $source from user settings and package directory. Session histories remain untouched.';
  String get actionRemove =>
      isItalian ? 'Rimuovi' : 'Remove';
  String get packageRemovedSuccess =>
      isItalian ? 'Pacchetto rimosso' : 'Package removed';

  String get pinNpmVersionTitle =>
      isItalian ? 'Blocca versione npm' : 'Pin npm version';
  String get semverVersionLabel =>
      isItalian ? 'Versione semver' : 'Semver version';
  String get actionPin =>
      isItalian ? 'Blocca' : 'Pin';
  String get confirmPinTitle =>
      isItalian ? 'Confermare versione bloccata?' : 'Confirm pinned version?';
  String confirmPinDesc(String source, String version) => isItalian
      ? '$source verrà impostato sulla versione $version.'
      : '$source will be set to version $version.';
  String get actionPinVersion =>
      isItalian ? 'Blocca versione' : 'Pin version';
  String get versionPinnedSuccess =>
      isItalian ? 'Versione bloccata' : 'Version pinned';

  String packageActionNotice(String successMessage, String source) => isItalian
      ? '$successMessage: $source. Riavvia Pi per applicare le modifiche.'
      : '$successMessage: $source. Restart Pi to apply changes.';
  String packageActionFailedNotice(Object error) => isItalian
      ? 'Operazione sul pacchetto non riuscita: $error'
      : 'Package operation failed: $error';

  String get retryAction =>
      isItalian ? 'Riprova' : 'Retry';
  String get noPackagesInstalled =>
      isItalian ? 'Nessun pacchetto Pi utente installato.' : 'No user Pi packages installed.';
  String get packagesInstalledTitle =>
      isItalian ? 'Pacchetti Pi installati' : 'Installed Pi Packages';
  String get packagesInstalledSubtitle => isItalian
      ? 'Pacchetti utente globali, gestiti dal package manager Pi. Modifiche attive al prossimo avvio di Pi.'
      : 'Global user packages managed by the Pi package manager. Changes take effect on next Pi startup.';
  String get unknownVersion =>
      isItalian ? 'versione sconosciuta' : 'unknown version';
  String updatePackageTooltip(String name) =>
      isItalian ? 'Aggiorna $name' : 'Update $name';
  String pinPackageTooltip(String name) =>
      isItalian ? 'Blocca versione $name' : 'Pin version for $name';
  String removePackageTooltip(String name) =>
      isItalian ? 'Rimuovi $name' : 'Remove $name';

  String get daemonStatusTitle =>
      isItalian ? 'Stato del daemon pi-agentd' : 'pi-agentd Daemon Status';
  String get daemonStatusSubtitle => isItalian
      ? 'Il daemon locale gestisce i processi Pi worker, il journal e il protocollo PCP/1.'
      : 'The local daemon manages Pi worker processes, the journal, and the PCP/1 protocol.';
  String get labelHttpWsPort =>
      isItalian ? 'Porta HTTP/WS' : 'HTTP/WS Port';
  String get labelConnecting =>
      isItalian ? 'In connessione...' : 'Connecting...';
  String get labelStatus =>
      isItalian ? 'Stato' : 'Status';
  String get labelNotConnected =>
      isItalian ? 'Non connesso' : 'Not connected';
  String get labelEndpointDetected =>
      isItalian ? 'Endpoint rilevato' : 'Endpoint detected';
  String get labelProtocol =>
      isItalian ? 'Protocollo' : 'Protocol';
  String get protocolPcp1 =>
      isItalian ? 'PCP/1 (JSON testuale)' : 'PCP/1 (textual JSON)';

  String get workerIdleTimeoutTitle =>
      isItalian ? 'Timeout inattività worker' : 'Worker idle timeout';
  String get workerIdleTimeoutSubtitle => isItalian
      ? 'Dopo quanto tempo di inattività i processi Pi in idle vengono terminati per risparmiare risorse (i worker occupati non vengono mai terminati).'
      : 'How long idle Pi worker processes run before termination to conserve resources (busy workers are never killed).';
  String get timeoutSavingStatus =>
      isItalian ? 'Salvataggio in corso...' : 'Saving...';
  String get timeoutUpdatedStatus =>
      isItalian ? 'Timeout aggiornato con successo!' : 'Timeout updated successfully!';
  String timeoutErrorStatus(Object error) =>
      isItalian ? 'Errore: $error' : 'Error: $error';

  String get timeoutNever =>
      isItalian ? 'Mai (0 min)' : 'Never (0 min)';
  String get timeout5Min =>
      isItalian ? '5 min' : '5 minutes';
  String get timeout15Min =>
      isItalian ? '15 min' : '15 minutes';
  String get timeout30Min =>
      isItalian ? '30 min (predefinito)' : '30 minutes (Default)';
  String get timeout1Hour =>
      isItalian ? '1 ora (60 min)' : '1 hour (60 min)';
  String get timeout2Hours =>
      isItalian ? '2 ore (120 min)' : '2 hours (120 min)';

  String get restartingDaemonStatus =>
      isItalian ? 'Riavvio in corso...' : 'Restarting...';
  String get restartDaemonBtn =>
      isItalian ? 'Riavvia daemon' : 'Restart Daemon';

  String get notificationsSectionTitle => isItalian
      ? 'Notifiche di sistema (macOS, Windows, Linux)'
      : 'System Notifications (macOS, Windows, Linux)';
  String get notificationsSectionSubtitle => isItalian
      ? 'Invia notifiche di sistema quando l\'agente completa una risposta o richiede una scelta/conferma e l\'applicazione non è a fuoco.'
      : 'Send system notifications when the agent finishes a response or requests a choice/confirmation and the app is unfocused.';
  String get notificationsSwitchTitle => isItalian
      ? 'Notifiche di sistema quando l\'app non è a fuoco'
      : 'System notifications when app is unfocused';

  // ---------------------------------------------------------------------------
  // Settings View: Appearance Details & Privacy & Terminal
  // ---------------------------------------------------------------------------
  String get themeJsonFilterLabel =>
      isItalian ? 'Tema JSON (*.json)' : 'JSON Theme (*.json)';
  String themeImportSuccess(String name) => isItalian
      ? 'Tema "$name" importato e attivato con successo!'
      : 'Theme "$name" imported and applied successfully!';
  String themeImportError(Object error) => isItalian
      ? 'Errore durante l\'importazione del tema: $error'
      : 'Error importing theme: $error';

  String get labelActiveTheme =>
      isItalian ? 'Tema attivo' : 'Active theme';
  String get labelLayoutDensity =>
      isItalian ? 'Densità layout' : 'Layout density';
  String get layoutDensityDefault =>
      isItalian ? 'Confortevole (1.0x)' : 'Comfortable (Default 1.0x)';
  String get labelFonts =>
      isItalian ? 'Caratteri' : 'Fonts';
  String fontsDetail(String ui, String mono) =>
      isItalian ? '$ui (UI) · $mono (codice)' : '$ui (UI) · $mono (Code)';
  String get themeDiagnosticsHeader =>
      isItalian ? 'Diagnostica tema:' : 'Theme diagnostics:';

  String get privacyTitle =>
      isItalian ? 'Informativa sulla privacy e tracciamento' : 'Privacy & Tracking Policy';
  String get privacyCardContent => isItalian
      ? 'PiFrame non invia alcun dato di utilizzo a server remoti. I log restano sul tuo computer; puoi esportarli manualmente dalla sezione diagnostica per condividerli con chi ti assiste.'
      : 'PiFrame does not send usage data to remote servers. Logs stay on your computer; you can manually export them from the Diagnostics tab to share with support.';
  String get privacyBulletPoints => isItalian
      ? '• Zero telemetria, zero analytics di terze parti (nessun Google Analytics, Mixpanel o Sentry).\n'
        '• Comunicazione locale confinata all\'interfaccia loopback 127.0.0.1 con token di autenticazione 256 bit.\n'
        '• Nessuna modifica ai file di sessione o configurazioni originali di Pi in ~/.pi/.'
      : '• Zero telemetry, zero third-party analytics (no Google Analytics, Mixpanel, or Sentry).\n'
        '• Local communication strictly bound to loopback interface 127.0.0.1 with 256-bit authentication token.\n'
        '• No modification to original Pi session files or configurations in ~/.pi/.';

  String get terminalTabTitle =>
      isItalian ? 'Terminale & Ambiente di esecuzione' : 'Terminal & Execution Environment';
  String get terminalTabSubtitle => isItalian
      ? 'Scegli se utilizzare il terminale integrato direttamente nell\'interfaccia o aprire il terminale nativo del sistema operativo (es. Windows terminal, PowerShell, CMD, WSL, o un eseguibile personalizzato).'
      : 'Choose whether to use the integrated terminal inside the interface or open the native OS terminal (e.g. Windows Terminal, PowerShell, CMD, WSL, or custom executable).';
  String get terminalPreferredModeHeader =>
      isItalian ? 'MODALITÀ PREFERITA' : 'PREFERRED MODE';
  String get terminalIntegratedTitle =>
      isItalian ? 'Terminale integrato (in PiFrame)' : 'Integrated terminal (in PiFrame)';
  String get terminalIntegratedSubtitle => isItalian
      ? 'Scrivi direttamente nella finestra di terminale integrata, con cronologia frecce su/giù e supporto shell di sistema.'
      : 'Type directly in the integrated terminal pane, with up/down arrow history and system shell support.';
  String get terminalNativeTitle => isItalian
      ? 'Terminale nativo OS (applicazione esterna)'
      : 'Native OS terminal (external application)';
  String get terminalNativeSubtitle => isItalian
      ? 'Apre una finestra di terminale esterna nativa direttamente nella cartella del repository.'
      : 'Opens an external native terminal window directly in the repository directory.';
  String get terminalNativeAppHeader =>
      isItalian ? 'APPLICAZIONE TERMINALE NATIVO (OS)' : 'NATIVE OS TERMINAL APPLICATION';
  String terminalNativeAppDefault(bool isWindows) => isItalian
      ? (isWindows
          ? 'Predefinito di sistema (Windows Terminal wt.exe / shell predefinita)'
          : 'Terminale predefinito di sistema')
      : (isWindows
          ? 'System default (Windows Terminal wt.exe / default shell)'
          : 'System default terminal');
  String get terminalPowershell => 'PowerShell (powershell.exe)';
  String get terminalCmd => 'Command Prompt (cmd.exe)';
  String get terminalWsl => 'WSL (Windows Subsystem for Linux)';
  String get terminalCustomApp => isItalian
      ? 'Applicazione o eseguibile personalizzato'
      : 'Custom application or executable';
  String get terminalBrowseBtn =>
      isItalian ? 'Sfoglia' : 'Browse';
  String get terminalExecutableFilterLabel =>
      isItalian ? 'Eseguibile' : 'Executable';
  String get terminalTestBtn =>
      isItalian ? 'Testa apertura terminale nativo' : 'Test opening native terminal';
  String get terminalTestSuccess => isItalian
      ? 'Terminale nativo avviato con successo!'
      : 'Native terminal launched successfully!';
  String get terminalTestFailed => isItalian
      ? 'Impossibile avviare il terminale con la configurazione scelta.'
      : 'Failed to launch terminal with current configuration.';

  // ---------------------------------------------------------------------------
  // Diagnostics Section
  // ---------------------------------------------------------------------------
  String get diagBundleCopiedRedacted => isItalian
      ? 'Bundle diagnostico copiato negli appunti (tutti i segreti sono stati redatti con [REDACTED])'
      : 'Diagnostic bundle copied to clipboard (all secrets redacted with [REDACTED])';
  String get diagBundleCopiedSnackBar => isItalian
      ? 'Bundle diagnostico copiato negli appunti!'
      : 'Diagnostic bundle copied to clipboard!';
  String diagExportError(Object error) => isItalian
      ? 'Errore durante esportazione: $error'
      : 'Error during export: $error';
  String get diagTitle => isItalian
      ? 'Diagnostica locale & Stato di sistema'
      : 'Local Diagnostics & System State';
  String get diagSubtitle => isItalian
      ? 'Tutti i dati di diagnostica restano sulla tua macchina locale. Nessun dato viene mai trasmesso a server esterni.'
      : 'All diagnostic data stays on your local machine. No data is ever sent to external servers.';
  String get diagRuntimeStateHeader =>
      isItalian ? 'STATO ATTUALE DEL RUNTIME' : 'CURRENT RUNTIME STATE';
  String get diagDaemonConnection =>
      isItalian ? 'Connessione daemon' : 'Daemon Connection';
  String get diagAppVersionLabel =>
      isItalian ? 'Versione PiFrame app' : 'PiFrame App Version';
  String get diagPcpProtocol =>
      isItalian ? 'Protocollo PCP' : 'PCP Protocol';
  String get diagArchivedSessions =>
      isItalian ? 'Sessioni archiviate' : 'Archived Sessions';
  String get diagRemoteTelemetry =>
      isItalian ? 'Telemetria remota' : 'Remote Telemetry';
  String get diagTelemetryDisabled =>
      isItalian ? 'DISABILITATA' : 'DISABLED (Zero Analytics)';
  String get diagExportBundleTitle =>
      isItalian ? 'Esporta bundle diagnostico' : 'Export Diagnostic Bundle';
  String get diagExportBundleDesc => isItalian
      ? 'Genera un rapporto diagnostico completo formattato in JSON. Tutti i token, credenziali e percorsi sensibili vengono automaticamente anonimizzati e redatti prima della copia negli appunti.'
      : 'Generates a full diagnostic report formatted in JSON. All sensitive tokens, credentials, and paths are automatically anonymized and redacted before copying to clipboard.';
  String get diagGenerating =>
      isItalian ? 'Generazione...' : 'Generating...';
  String get diagCopyBundleBtn => isItalian
      ? 'Copia bundle diagnostico negli appunti'
      : 'Copy Diagnostic Bundle to Clipboard';

  // ---------------------------------------------------------------------------
  // Pi CLI Section
  // ---------------------------------------------------------------------------
  String get piCliTitle =>
      isItalian ? 'Interfaccia Pi CLI' : 'Pi CLI Interface';
  String get piCliSubtitle => isItalian
      ? 'Esegui comandi e aggiornamenti ufficiali di Pi coding agent direttamente da PiFrame.'
      : 'Run official Pi Coding Agent commands and updates directly from PiFrame.';
  String get piCliFastCommands =>
      isItalian ? 'COMANDI RAPIDI' : 'QUICK COMMANDS';
  String get piCliCustomCmdHeader =>
      isItalian ? 'COMANDO PERSONALIZZATO' : 'CUSTOM COMMAND';
  String get piCliCustomCmdHint => isItalian
      ? 'es. update --force, auth check, mcp login <server>...'
      : 'e.g. update --force, auth check, mcp login <server>...';
  String get piCliRunBtn =>
      isItalian ? 'Esegui' : 'Run';
  String get piCliConsoleOutputHeader =>
      isItalian ? 'OUTPUT CONSOLE' : 'CONSOLE OUTPUT';
  String piCliRunningNotice(String cmd) =>
      isItalian ? 'In esecuzione $cmd...' : 'Running $cmd...';
  String get piCliStopBtn =>
      isItalian ? 'Interrompi' : 'Stop';
  String get piCliSuccessCode =>
      isItalian ? 'Successo (0)' : 'Success (0)';
  String piCliExitCode(int code) =>
      isItalian ? 'Codice $code' : 'Exit code $code';
  String get piCliCopyOutputTooltip =>
      isItalian ? 'Copia output' : 'Copy output';
  String get piCliClearOutputTooltip =>
      isItalian ? 'Cancella output' : 'Clear output';
  String get piCliEmptyOutput => isItalian
      ? 'Nessun output. Seleziona un comando sopra o digita un comando personalizzato per iniziare.'
      : 'No output yet. Select a command above or type a custom command to get started.';
  String get piCliSystemPathNotice => isItalian
      ? 'PiFrame utilizza il comando `pi` configurato nel PATH di sistema.'
      : 'PiFrame uses the `pi` command configured in system PATH.';
  String get piCliRecheckBtn =>
      isItalian ? 'Ricontrolla' : 'Recheck';
  String get piCliManageMcpBtn =>
      isItalian ? 'Gestisci' : 'Manage';
  String get piCliInProgress =>
      isItalian ? 'In corso...' : 'Running...';
  String get piCliMcpCardTooltip => isItalian
      ? 'Clicca sulla scheda per visualizzare e abilitare/disabilitare i server MCP'
      : 'Click card to view and enable/disable MCP servers';
  String get piCliDesktopOnly => isItalian
      ? 'I comandi Pi sono disponibili solo nell\'app desktop.'
      : 'Pi commands are available only in the desktop app.';
  String piCliProcessCompleted(int code, int ms) => isItalian
      ? '\n[Processo completato con codice $code in ${ms}ms]\n'
      : '\n[Process completed with code $code in ${ms}ms]\n';
  String piCliExecutionError(Object error) => isItalian
      ? '\nErrore durante l\'esecuzione del comando: $error\n'
      : '\nError executing command: $error\n';
  String get piCliOutputCopiedSnackBar => isItalian
      ? 'Output del comando copiato negli appunti'
      : 'Command output copied to clipboard';
  String get piCliCommandCancelled => isItalian
      ? '\n[Comando interrotto dall\'utente]\n'
      : '\n[Command stopped by user]\n';

  // Pi built-in commands
  String get piCmdUpdateCliLabel =>
      isItalian ? 'Aggiorna Pi CLI' : 'Update Pi CLI';
  String get piCmdUpdateCliDesc => isItalian
      ? 'Aggiorna l\'eseguibile di Pi all\'ultima versione stabile disponibile.'
      : 'Update the Pi executable to the latest stable release.';

  String get piCmdUpdateExtLabel =>
      isItalian ? 'Aggiorna estensioni' : 'Update Extensions';
  String get piCmdUpdateExtDesc => isItalian
      ? 'Aggiorna tutti i pacchetti ed estensioni utente installati.'
      : 'Update all installed user packages and extensions.';

  String get piCmdUpdateModelsLabel =>
      isItalian ? 'Aggiorna catalogo modelli' : 'Update Model Catalog';
  String get piCmdUpdateModelsDesc => isItalian
      ? 'Sincronizza e aggiorna il catalogo dei modelli AI supportati.'
      : 'Sync and update the supported AI models catalog.';

  String get piCmdUpdateAllLabel =>
      isItalian ? 'Aggiorna tutto' : 'Update All';
  String get piCmdUpdateAllDesc => isItalian
      ? 'Aggiorna contemporaneamente Pi CLI e tutte le estensioni installate.'
      : 'Simultaneously update Pi CLI and all installed extensions.';

  String get piCmdListLabel =>
      isItalian ? 'Elenco estensioni' : 'List Extensions';
  String get piCmdListDesc => isItalian
      ? 'Visualizza tutte le estensioni e i pacchetti utente attualmente installati.'
      : 'Display all currently installed user extensions and packages.';

  String get piCmdMcpListLabel =>
      isItalian ? 'Stato server MCP' : 'MCP Server Status';
  String get piCmdMcpListDesc => isItalian
      ? 'Verifica la connessione, lo stato e gli strumenti dei server MCP configurati.'
      : 'Verify connection, status, and tools for configured MCP servers.';

  String get piCmdModelsLabel =>
      isItalian ? 'Modelli disponibili' : 'Available Models';
  String get piCmdModelsDesc => isItalian
      ? 'Elenca tutti i modelli LLM disponibili per il coding assistant.'
      : 'List all LLM models available for the coding assistant.';

  String get piCmdVersionLabel =>
      isItalian ? 'Versione Pi CLI' : 'Pi CLI Version';
  String get piCmdVersionDesc => isItalian
      ? 'Controlla la versione corrente di Pi installata nel sistema.'
      : 'Check the current Pi version installed on the system.';

  // ---------------------------------------------------------------------------
  // MCP Servers Dialog
  // ---------------------------------------------------------------------------
  String get mcpDesktopOnly => isItalian
      ? 'La configurazione MCP è disponibile solo su desktop.'
      : 'MCP configuration is available on desktop only.';
  String mcpLoadError(Object error) => isItalian
      ? 'Impossibile caricare i server MCP: $error'
      : 'Failed to load MCP servers: $error';
  String mcpSaveError(Object error) => isItalian
      ? 'Errore nel salvataggio: $error'
      : 'Error saving changes: $error';
  String get mcpDialogTitle =>
      isItalian ? 'Server MCP Disponibili' : 'Available MCP Servers';
  String get mcpDialogSubtitle => isItalian
      ? 'Configura e attiva o disattiva i server MCP per il coding agent.'
      : 'Configure and enable or disable MCP servers for the coding agent.';
  String get mcpRefreshListTooltip =>
      isItalian ? 'Aggiorna elenco' : 'Refresh list';
  String get mcpLoadingServers => isItalian
      ? 'Caricamento server MCP in corso...'
      : 'Loading MCP servers...';
  String get mcpEmptyTitle => isItalian
      ? 'Nessun server MCP configurato'
      : 'No MCP servers configured';
  String get mcpEmptySubtitle => isItalian
      ? 'Aggiungi un server con "pi mcp add <nome> -- <comando>"\noppure modifica ~/.pi/agent/mcp.json.'
      : 'Add a server with "pi mcp add <name> -- <command>"\nor edit ~/.pi/agent/mcp.json.';
  String get mcpZeroServers =>
      isItalian ? '0 server' : '0 servers';
  String mcpActiveServersCount(int enabled, int total) => isItalian
      ? '$enabled su $total server attivi'
      : '$enabled of $total servers active';
  String get mcpStatusDisabled =>
      isItalian ? 'Disabilitato' : 'Disabled';
  String get mcpStatusConnected =>
      isItalian ? 'Connesso' : 'Connected';
  String get mcpStatusFailed =>
      isItalian ? 'Non connesso' : 'Disconnected';
  String get mcpStatusEnabled =>
      isItalian ? 'Abilitato' : 'Enabled';
  String get mcpScopeProject =>
      isItalian ? 'Progetto' : 'Project';
  String mcpToolsCount(int count) =>
      isItalian ? '$count tool' : '$count tools';
  String get mcpCopyCommandTooltip =>
      isItalian ? 'Copia comando' : 'Copy command';
  String get mcpCommandCopiedSnackBar =>
      isItalian ? 'Comando copiato' : 'Command copied';

  // ---------------------------------------------------------------------------
  // Remote Access Section
  // ---------------------------------------------------------------------------
  String get remoteTitle =>
      isItalian ? 'Connessione remota sicura' : 'Secure Remote Connection';
  String get remoteSubtitle => isItalian
      ? 'Accedi al tuo Pi dallo smartphone o dal browser in mobilità. Tunnel crittografato, associazione one-time via QR code con URL fragment (#pair=...), token per-dispositivo con scadenza e controllo granulare dei permessi (view o control).'
      : 'Access your Pi from smartphone or browser on the go. Encrypted tunnel, one-time QR code pairing via URL fragment (#pair=...), expiring per-device tokens, and granular permission control (view or control).';
  String get remoteEnableTitle =>
      isItalian ? 'Abilita accesso remoto' : 'Enable Remote Access';
  String get remoteStatusActive =>
      isItalian ? 'ATTIVO' : 'ACTIVE';
  String get remoteStatusStarting =>
      isItalian ? 'AVVIO...' : 'STARTING...';
  String get remoteStatusError =>
      isItalian ? 'ERRORE' : 'ERROR';
  String get remoteStatusDisabled =>
      isItalian ? 'DISATTIVATO' : 'DISABLED';
  String get remoteEnabledDesc => isItalian
      ? 'Il listener remoto dedicato è attivo. Inquadra il QR code per associare un dispositivo.'
      : 'Dedicated remote listener is active. Scan QR code to pair a device.';
  String get remoteDisabledDesc => isItalian
      ? 'Disattivato (opt-in). Nessuna connessione esterna è accettata.'
      : 'Disabled (opt-in). No external connections accepted.';
  String get remotePairSmartphoneTitle =>
      isItalian ? 'Associa il tuo smartphone' : 'Pair Your Smartphone';
  String get remotePairStep1 => isItalian
      ? '1. Inquadra il QR con la fotocamera del telefono'
      : '1. Scan the QR code with your phone camera';
  String get remotePairStep1Desc => isItalian
      ? 'Aprirà la webapp PiFrame con associazione sicura monouso via fragment crittografico.'
      : 'Opens the PiFrame web app with secure one-time pairing via cryptographic fragment.';
  String get remotePairExpired =>
      isItalian ? 'Scaduto' : 'Expired';
  String remotePairExpiresIn(int mins, String secs) => isItalian
      ? 'Scade tra ${mins}m ${secs}s'
      : 'Expires in ${mins}m ${secs}s';
  String get remoteNewQrBtn =>
      isItalian ? 'Nuovo codice QR' : 'New QR code';
  String get remoteCopyPairLinkBtn => isItalian
      ? 'Copia link di associazione'
      : 'Copy Pairing Link';
  String get remotePairLinkCopiedSnackBar => isItalian
      ? 'Link di associazione copiato negli appunti!'
      : 'Pairing link copied to clipboard!';
  String get remoteOpenInBrowserTooltip =>
      isItalian ? 'Apri nel browser' : 'Open in browser';
  String get remotePublicUrlLabel =>
      isItalian ? 'URL Pubblico: ' : 'Public URL: ';
  String get remoteDefaultModeTitle => isItalian
      ? 'Modalità predefinita per nuovi dispositivi'
      : 'Default Mode for New Devices';
  String get remoteDefaultModeSubtitle => isItalian
      ? 'I nuovi dispositivi associati ricevono questa modalità. Puoi modificarla per singolo dispositivo nella lista sottostante.'
      : 'Newly paired devices receive this mode. You can adjust per device in the list below.';
  String get remoteSegmentView =>
      isItalian ? 'Visualizzazione' : 'View Only (View)';
  String get remoteSegmentControl =>
      isItalian ? 'Controllo' : 'Control (Control)';
  String get remoteModeViewExplanation => isItalian
      ? 'La modalità Visualizzazione consente di consultare sessioni, log e file in sola lettura, con possibilità di abortire l\'agente in caso di emergenza. Nessun prompt o modifica consentita.'
      : 'View mode allows read-only access to sessions, logs, and files, with emergency agent abort. No prompts or modifications allowed.';
  String get remoteModeControlExplanation => isItalian
      ? 'La modalità Controllo consente di inviare messaggi, avviare sessioni ed eseguire azioni complete tramite l\'agente.'
      : 'Control mode allows sending prompts, starting sessions, and full execution through the agent.';
  String remoteAuthorizedDevicesTitle(int count) => isItalian
      ? 'Dispositivi autorizzati ($count)'
      : 'Authorized Devices ($count)';
  String get remoteRevokeAllBtn =>
      isItalian ? 'Revoca tutti' : 'Revoke All';
  String get remoteNoDevicesAuthorized => isItalian
      ? 'Nessun dispositivo autorizzato. Inquadra il QR code per associare il tuo smartphone.'
      : 'No authorized devices. Scan the QR code to pair your smartphone.';
  String get remoteUnknownDevice =>
      isItalian ? 'Dispositivo sconosciuto' : 'Unknown Device';
  String get remoteLocalIp =>
      isItalian ? 'Locale' : 'Local';
  String get remoteNeverUsed =>
      isItalian ? 'Mai' : 'Never';
  String remoteDeviceInfoLine(String ip, String last, String expires) => isItalian
      ? 'IP: $ip • Ultima attività: $last • Scade: $expires'
      : 'IP: $ip • Last active: $last • Expires: $expires';
  String get remoteRevokeBtn =>
      isItalian ? 'Revoca' : 'Revoke';
  String get remoteRevokeDeviceDialogTitle =>
      isItalian ? 'Revoca dispositivo' : 'Revoke Device';
  String remoteRevokeDeviceDialogContent(String name) => isItalian
      ? 'Vuoi revocare l\'accesso a "$name"? La connessione verrà terminata immediatamente.'
      : 'Revoke access for "$name"? Connection will be terminated immediately.';
  String get remoteRevokeAllDialogTitle => isItalian
      ? 'Revoca tutti i dispositivi'
      : 'Revoke All Devices';
  String get remoteRevokeAllDialogContent => isItalian
      ? 'Tutte le sessioni remote verranno disconnesse e i token invalidati immediatamente. Continuare?'
      : 'All remote sessions will be disconnected and tokens invalidated immediately. Continue?';
  String get remoteControlConfirmTitle => isItalian
      ? 'Conferma modalità controllo'
      : 'Confirm Control Mode';
  String remoteControlConfirmContent(String name) => isItalian
      ? 'Stai concedendo i permessi di CONTROLLO COMPLETO a "$name".\n\n'
        'Questo dispositivo potrà inviare prompt ed eseguire comandi sul tuo computer con gli stessi privilegi del tuo utente.'
      : 'You are granting FULL CONTROL permissions to "$name".\n\n'
        'This device will be able to send prompts and execute commands on your computer with your user privileges.';
  String get remoteGrantControlBtn =>
      isItalian ? 'Concedi controllo' : 'Grant Control';
  String get remoteProviderConfigTitle => isItalian
      ? 'Configurazione provider tunnel'
      : 'Tunnel Provider Configuration';
  String get remoteProviderTailscale => isItalian
      ? 'Tailscale (Consigliato: Permanente, privato e sicuro)'
      : 'Tailscale (Recommended: Permanent, Private & Secure)';
  String get remoteProviderCloudflared => isItalian
      ? 'Cloudflare quick tunnel (Temporaneo, nessun account)'
      : 'Cloudflare Quick Tunnel (Temporary, no account needed)';
  String get remoteProviderCustom => isItalian
      ? 'Altro tunnel personalizzato / Reverse proxy'
      : 'Custom Tunnel / Reverse Proxy';

  String get remoteTailscaleNotInstalledTitle => isItalian
      ? 'Tailscale non è installato su questo computer'
      : 'Tailscale is not installed on this computer';
  String get remoteTailscaleNotInstalledDesc => isItalian
      ? 'Tailscale crea una rete privata sicura mesh (WireGuard) tra i tuoi dispositivi con certificato HTTPS e nome di dominio fisso permanente.'
      : 'Tailscale creates a secure private Mesh network (WireGuard) between your devices with HTTPS certificate and fixed permanent domain.';
  String get remoteTailscaleInstallAutoBtn => isItalian
      ? 'Installa Tailscale automaticamente'
      : 'Install Tailscale automatically';
  String get remoteTailscaleInstallingBtn => isItalian
      ? 'Avvio installazione...'
      : 'Starting installation...';
  String get remoteTailscaleNotRunning => isItalian
      ? 'Tailscale è installato ma non è connesso. Apri l\'app Tailscale ed effettua il login per attivare la rete.'
      : 'Tailscale is installed but not connected. Open the Tailscale app and sign in to activate the network.';
  String get remoteTailscaleActiveTitle => isItalian
      ? 'Tailscale è attivo e connesso'
      : 'Tailscale is active and connected';
  String remoteTailscalePermanentAddress(String domain) => isItalian
      ? 'Indirizzo permanente: https://$domain'
      : 'Permanent address: https://$domain';
  String get remoteTailscaleCustomizeHostname => isItalian
      ? 'Personalizza il nome host della macchina:'
      : 'Customize machine hostname:';
  String get remoteTailscaleHostnameLabel => isItalian
      ? 'Nome host Tailscale (es. pi-frame)'
      : 'Tailscale hostname (e.g. pi-frame)';
  String get remoteTailscaleSaveNameBtn =>
      isItalian ? 'Salva nome' : 'Save hostname';

  String get remoteCloudflaredDetectedTitle => isItalian
      ? 'cloudflared rilevato e pronto all\'uso'
      : 'cloudflared detected and ready to use';
  String get remoteCloudflaredNotFoundTitle => isItalian
      ? 'Eseguibile cloudflared non trovato'
      : 'cloudflared executable not found';
  String get remoteCloudflaredNotFoundDesc => isItalian
      ? 'Per utilizzare i quick tunnel di cloudflare è necessario l\'eseguibile ufficiale open-source di cloudflare.'
      : 'The official open-source Cloudflare binary is required to use Cloudflare Quick Tunnels.';
  String get remoteCloudflaredInstallAutoBtn => isItalian
      ? 'Installa cloudflared automaticamente'
      : 'Install cloudflared automatically';
  String get remoteCloudflaredInstallingBtn => isItalian
      ? 'Download e installazione in corso...'
      : 'Downloading and installing...';
  String get remoteCloudflaredInstallNote => isItalian
      ? 'Verrà scaricato in ~/.piframe/bin/cloudflared senza richiedere permessi di amministratore o riavvii.'
      : 'Downloaded to ~/.piframe/bin/cloudflared without administrator privileges or restarts.';
  String remoteDedicatedListenerPort(int port) => isItalian
      ? 'Porta del listener remoto dedicato: $port (127.0.0.1:$port)'
      : 'Dedicated remote listener port: $port (127.0.0.1:$port)';
  String get remoteCustomHttpsUrlLabel => isItalian
      ? 'URL Pubblico HTTPS (es. https://my-node.ts.net)'
      : 'Public HTTPS URL (e.g. https://my-node.ts.net)';
  String get remoteCustomCommandLabel => isItalian
      ? 'Comando tunnel (eseguito senza shell, "\$PORT" sostituito con la porta listener)'
      : 'Tunnel command (executed without shell, "\$PORT" replaced with listener port)';
  String remoteCloudflaredReadySnackBar(String path) => isItalian
      ? 'cloudflared scaricato e pronto in $path!'
      : 'cloudflared downloaded and ready at $path!';
  String remoteCloudflaredInstallError(Object error) => isItalian
      ? 'Errore durante l\'installazione di cloudflared: $error'
      : 'Error installing cloudflared: $error';
  String get remoteTailscaleInstallDefaultToast => isItalian
      ? 'Installazione di Tailscale avviata! Conferma il prompt di Windows.'
      : 'Tailscale installation started! Confirm the system prompt.';
  String remoteTailscaleInstallError(Object error) => isItalian
      ? 'Errore durante l\'installazione di Tailscale: $error'
      : 'Error installing Tailscale: $error';
  String remoteTailscaleDomainUpdatedToast(String domain) => isItalian
      ? 'Nome host Tailscale aggiornato! Nuovo dominio: $domain'
      : 'Tailscale hostname updated! New domain: $domain';
  String remoteTailscaleRenameError(Object error) => isItalian
      ? 'Errore durante la ridenominazione: $error'
      : 'Error during rename: $error';
  String get remoteTailscaleMissingDialogTitle => isItalian
      ? 'Tailscale non installato'
      : 'Tailscale not installed';
  String get remoteTailscaleMissingDialogContent => isItalian
      ? 'Per utilizzare il tunnel permanente Tailscale è necessario installare Tailscale sul PC.\n\n'
        'Vuoi avviare l\'installazione automatica adesso?'
      : 'Using permanent Tailscale tunnels requires Tailscale installed on this PC.\n\n'
        'Start automatic installation now?';
  String get remoteInstallTailscaleBtn => isItalian
      ? 'Installa Tailscale'
      : 'Install Tailscale';
  String get remoteCloudflaredMissingDialogTitle => isItalian
      ? 'cloudflared richiesto'
      : 'cloudflared required';
  String get remoteCloudflaredMissingDialogContent => isItalian
      ? 'Per avviare la connessione remota con cloudflare è necessario l\'eseguibile ufficiale cloudflared.\n\n'
        'Vuoi scaricarlo e installarlo automaticamente in ~/.piframe/bin/? Non richiede permessi di amministratore.'
      : 'Starting a remote connection with Cloudflare requires the official cloudflared binary.\n\n'
        'Download and install automatically to ~/.piframe/bin/? Does not require admin privileges.';
  String get remoteInstallAndStartBtn => isItalian
      ? 'Installa e avvia'
      : 'Install & Start';

  // ---------------------------------------------------------------------------
  // Theme Editor Dialog
  // ---------------------------------------------------------------------------
  String get themeEditorSuggestedColors =>
      isItalian ? 'Colori suggeriti' : 'Suggested Colors';
  String get themeEditorApplyColor =>
      isItalian ? 'Applica' : 'Apply';
  String get themeEditorNameEmptyError => isItalian
      ? 'Il nome del tema non può essere vuoto'
      : 'Theme name cannot be empty';
  String themeEditorSavedSuccess(String name) => isItalian
      ? 'Tema "$name" salvato e attivato con successo!'
      : 'Theme "$name" saved and applied successfully!';
  String themeEditorSaveError(Object error) => isItalian
      ? 'Errore durante il salvataggio: $error'
      : 'Error during saving: $error';
  String get themeEditorPreviewWorking =>
      isItalian ? 'In corso' : 'Working';
  String get themeEditorPreviewBentoCard =>
      isItalian ? 'Scheda Bento & Superfici' : 'Bento Card & Surfaces';
  String get themeEditorPreviewBentoDesc => isItalian
      ? 'Testo secondario / descrittivo del tema in modifica.'
      : 'Secondary / descriptive text for current theme in edit.';
  String get themeEditorPreviewAccentBtn =>
      isItalian ? 'Pulsante accento' : 'Accent Button';
  String get themeEditorPreviewSecondaryBtn =>
      isItalian ? 'Pulsante secondario' : 'Secondary Button';
  String get themeEditorPreviewCodeComment =>
      isItalian ? '// Codice di esempio\n' : '// Code sample\n';

  // Color row labels
  String get colorLabelBackground =>
      isItalian ? 'Sfondo principale' : 'Main Background';
  String get colorLabelSurface =>
      isItalian ? 'Superficie bento' : 'Bento Surface (Card)';
  String get colorLabelSurfaceElevated =>
      isItalian ? 'Superficie elevata (pannelli)' : 'Elevated Surface (Panels)';
  String get colorLabelBorder =>
      isItalian ? 'Bordi & Separatori' : 'Borders & Separators';
  String get colorLabelBorderStrong =>
      isItalian ? 'Bordi evidenziati' : 'Highlighted Borders';
  String get colorLabelAccent =>
      isItalian ? 'Colore accento (primario)' : 'Accent Color (Primary)';
  String get colorLabelAccentContrast =>
      isItalian ? 'Testo su accento' : 'Text on Accent';
  String get colorLabelFocusRing =>
      isItalian ? 'Focus ring / Selezione' : 'Focus Ring / Selection';
  String get colorLabelTextPrimary =>
      isItalian ? 'Testo primario' : 'Primary Text';
  String get colorLabelTextSecondary =>
      isItalian ? 'Testo secondario' : 'Secondary Text';
  String get colorLabelTextMuted =>
      isItalian ? 'Testo disattivato / Muted' : 'Disabled / Muted Text';
  String get colorLabelAgentWorking =>
      isItalian ? 'Agente in corso' : 'Agent Working';
  String get colorLabelAgentSettled =>
      isItalian ? 'Agente a riposo' : 'Agent Settled';
  String get colorLabelAgentRetrying =>
      isItalian ? 'Agente in nuovo tentativo' : 'Agent Retrying';
  String get colorLabelAgentCompacting =>
      isItalian ? 'Agente compattazione' : 'Agent Compacting';
  String get colorLabelDanger =>
      isItalian ? 'Errore / pericolo' : 'Error / Danger';
  String get colorLabelKeyword =>
      isItalian ? 'Parole chiave' : 'Keywords (Keyword)';
  String get colorLabelFunction =>
      isItalian ? 'Funzioni / metodi' : 'Functions / Methods (Function)';
  String get colorLabelString =>
      isItalian ? 'Stringhe' : 'Strings (String)';
  String get colorLabelNumber =>
      isItalian ? 'Numeri' : 'Numbers (Number)';
  String get colorLabelComment =>
      isItalian ? 'Commenti' : 'Comments (Comment)';

  // ---------------------------------------------------------------------------
  // Updates Section
  // ---------------------------------------------------------------------------
  String get confirmInstallDialogTitle =>
      isItalian ? 'Confermare installazione?' : 'Confirm installation?';
  String confirmInstallDialogContent(String? assetName) => isItalian
      ? 'PiFrame verrà chiuso per avviare il processo di installazione dell\'aggiornamento${assetName != null ? " ($assetName)" : ""}.\n\nAssicurati che non ci siano comandi critici in esecuzione.'
      : 'PiFrame will close to launch update installation${assetName != null ? " ($assetName)" : ""}.\n\nEnsure no critical commands are currently executing.';
  String get installAndRestartBtn =>
      isItalian ? 'Installa e riavvia' : 'Install & Restart';
  String get updatesTitle =>
      isItalian ? 'Aggiornamenti PiFrame' : 'PiFrame Updates';
  String get updatesSubtitle => isItalian
      ? 'Verifica e scarica le nuove versioni ufficiali rilasciate sul repository GitHub di PiFrame.'
      : 'Check and download official new releases from the PiFrame GitHub repository.';
  String updatesInstalledVersion(String currentVer) =>
      isItalian ? 'Versione installata: v$currentVer' : 'Installed version: v$currentVer';
  String get updatesNewVersionBadge =>
      isItalian ? 'Nuova versione!' : 'New version!';
  String updatesLastChecked(String dt) =>
      isItalian ? 'Ultima verifica: $dt' : 'Last checked: $dt';
  String get updatesNoRecentCheck => isItalian
      ? 'Nessuna verifica recente effettuata'
      : 'No recent checks performed';
  String get updatesChecking =>
      isItalian ? 'Controllo in corso...' : 'Checking...';
  String get updatesCheckBtn =>
      isItalian ? 'Verifica disponibilità' : 'Check for updates';
  String get updatesUpToDateTitle => isItalian
      ? 'PiFrame è aggiornato all\'ultima versione disponibile'
      : 'PiFrame is up to date';
  String updatesUpToDateDesc(String currentVer) => isItalian
      ? 'Non sono presenti aggiornamenti più recenti di v$currentVer su GitHub.'
      : 'No updates newer than v$currentVer found on GitHub.';
  String get updatesCheckErrorTitle => isItalian
      ? 'Errore durante il controllo degli aggiornamenti'
      : 'Error checking for updates';
  String get updatesUnexpectedError =>
      isItalian ? 'Errore imprevisto' : 'Unexpected error';
  String get updatesAutoScheduleTitle =>
      isItalian ? 'Pianificazione automatica' : 'Automatic Schedule';
  String get updatesAutoScheduleSubtitle => isItalian
      ? 'Configura il controllo periodico degli aggiornamenti in background.'
      : 'Configure background periodic update checks.';
  String get updatesAutoCheckSwitchTitle => isItalian
      ? 'Verifica automaticamente la presenza di aggiornamenti'
      : 'Automatically check for updates';
  String get updatesAutoCheckSwitchSubtitle => isItalian
      ? 'Disattivato per impostazione predefinita per tutelare la privacy e prevenire chiamate di rete non richieste.'
      : 'Disabled by default to protect privacy and prevent unrequested network calls.';
  String get updatesCheckFrequencyLabel =>
      isItalian ? 'Frequenza di controllo:' : 'Check frequency:';

  String updateIntervalLabel(UpdateCheckInterval interval) {
    if (isItalian) {
      return interval.label;
    }
    switch (interval) {
      case UpdateCheckInterval.daily:
        return 'Every day';
      case UpdateCheckInterval.weekly:
        return 'Every week (recommended)';
      case UpdateCheckInterval.monthly:
        return 'Every month';
    }
  }

  String get updatesPrivacySafetyNotice => isItalian
      ? 'Privacy e sicurezza: il controllo aggiornamenti interroga esclusivamente le release pubbliche di GitHub tramite connessione HTTPS protetta. Nessun dato utente, token, sessione o informazione diagnostica viene trasmesso. Nessuna installazione viene mai eseguita senza la tua esplicita autorizzazione.'
      : 'Privacy & safety: the update check exclusively queries public GitHub releases over secure HTTPS. No user data, tokens, sessions, or diagnostics are transmitted. No installation ever runs without your explicit authorization.';
  String updatesPublishedAt(String dt) =>
      isItalian ? 'Pubblicato il $dt' : 'Published on $dt';
  String get updatesNotesOnGithub =>
      isItalian ? 'Note su GitHub' : 'Notes on GitHub';
  String updatesInstallerFile(String name, String size) =>
      isItalian ? 'File installer: $name ($size)' : 'Installer asset: $name ($size)';
  String get updatesReadyToInstall =>
      isItalian ? 'Pronto per l\'installazione' : 'Ready to install';
  String get updatesLaunchingInstaller => isItalian
      ? 'Avvio programma di installazione in corso...'
      : 'Launching installer...';
  String get updatesDownloadBtn =>
      isItalian ? 'Scarica aggiornamento' : 'Download update';
  String get updatesDownloadManuallyBtn => isItalian
      ? 'Scarica manualmente da GitHub'
      : 'Download manually from GitHub';
}
