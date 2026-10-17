import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../data/theme/theme_providers.dart';
import '../../data/notifications/notification_providers.dart';
import 'diagnostics.dart';
import 'pi_cli_section.dart';
import 'remote_section.dart';
import 'updates_section.dart';

class SettingsView extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final int initialTabIndex;

  const SettingsView({
    super.key,
    required this.onClose,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _workerIdleTimeoutMinutes = 30;
  bool _isLoadingConfig = true;
  String? _configStatusMessage;
  bool _isLoadingPackages = true;
  bool _isWorkingWithPackage = false;
  String? _packageError;
  List<Map<String, dynamic>> _packages = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 8,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _fetchDaemonConfig();
    _fetchPiPackages();
  }

  Future<void> _fetchDaemonConfig() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      if (mounted) {
        setState(() => _isLoadingConfig = false);
      }
      return;
    }

    try {
      final res = await client.getDaemonConfig();
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final ms = (data['workerIdleTimeoutMs'] as num?)?.toInt() ?? 1800000;
      if (mounted) {
        setState(() {
          _workerIdleTimeoutMinutes = (ms / 60000).round();
          _isLoadingConfig = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingConfig = false;
        });
      }
    }
  }

  Future<void> _fetchPiPackages() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      if (mounted) {
        setState(() {
          _packages = [];
          _packageError = 'Daemon non connesso';
          _isLoadingPackages = false;
        });
      }
      return;
    }
    setState(() {
      _isLoadingPackages = true;
      _packageError = null;
    });
    try {
      final result = await client.listPiPackages();
      final data = result['data'] as Map<String, dynamic>? ?? result;
      final packages = (data['packages'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      if (mounted) setState(() => _packages = packages);
    } catch (error) {
      if (mounted) setState(() => _packageError = error.toString());
    } finally {
      if (mounted) setState(() => _isLoadingPackages = false);
    }
  }

  Future<bool> _confirmPackageAction(
    String title,
    String message,
    String confirmation,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmation),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _performPackageAction(
    String source,
    Future<Map<String, dynamic>> Function(PcpClient client) action, {
    required String successMessage,
  }) async {
    final client = ref.read(pcpClientProvider);
    if (client == null || _isWorkingWithPackage) return;
    setState(() => _isWorkingWithPackage = true);
    try {
      await action(client);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$successMessage: $source. Riavvia Pi per applicare le modifiche.',
            ),
          ),
        );
      }
      await _fetchPiPackages();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Operazione sul pacchetto non riuscita: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isWorkingWithPackage = false);
    }
  }

  Future<void> _updatePackage(Map<String, dynamic> package) async {
    final source = package['source'].toString();
    if (!await _confirmPackageAction(
      'Aggiornare il pacchetto?',
      'Pi aggiornerà $source usando il package manager installato. Il codice aggiornato verrà caricato al prossimo avvio di Pi.',
      'Aggiorna',
    )) {
      return;
    }
    await _performPackageAction(
      source,
      (client) => client.updatePiPackage(source),
      successMessage: 'Pacchetto aggiornato',
    );
  }

  Future<void> _removePackage(Map<String, dynamic> package) async {
    final source = package['source'].toString();
    if (!await _confirmPackageAction(
      'Rimuovere il pacchetto?',
      'Pi rimuoverà $source dalle impostazioni utente e dalla directory dei pacchetti. Le cronologie delle sessioni non vengono modificate.',
      'Rimuovi',
    )) {
      return;
    }
    await _performPackageAction(
      source,
      (client) => client.removePiPackage(source),
      successMessage: 'Pacchetto rimosso',
    );
  }

  Future<void> _pinPackage(Map<String, dynamic> package) async {
    final source = package['source'].toString();
    final currentVersion =
        (package['pinnedVersion'] ?? package['version'] ?? '').toString();
    var version = currentVersion;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Blocca versione npm'),
          content: TextFormField(
            initialValue: currentVersion,
            onChanged: (value) => setDialogState(() => version = value.trim()),
            decoration: const InputDecoration(
              labelText: 'Versione semver',
              hintText: '1.2.3',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: version.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, version),
              child: const Text('Blocca'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (!await _confirmPackageAction(
      'Confermare versione bloccata?',
      '$source verrà impostato sulla versione $selected.',
      'Blocca versione',
    )) {
      return;
    }
    await _performPackageAction(
      source,
      (client) => client.pinPiPackage(source, selected),
      successMessage: 'Versione bloccata',
    );
  }

  Widget _packageList(CrustTokens tokens) {
    if (_isLoadingPackages) {
      return Center(child: CircularProgressIndicator(color: tokens.accent));
    }
    if (_packageError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_packageError!, style: TextStyle(color: tokens.danger)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _fetchPiPackages,
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
          ],
        ),
      );
    }
    if (_packages.isEmpty) {
      return Center(
        child: Text(
          'Nessun pacchetto Pi utente installato.',
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Pacchetti Pi installati',
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pacchetti utente globali, gestiti dal package manager Pi. Modifiche attive al prossimo avvio di Pi.',
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
        if (_isWorkingWithPackage) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(color: tokens.accent),
        ],
        const SizedBox(height: 16),
        for (final package in _packages) _buildPackageCard(tokens, package),
      ],
    );
  }

  Widget _buildPackageCard(CrustTokens tokens, Map<String, dynamic> package) {
    final source = package['source']?.toString() ?? '';
    final name = package['name']?.toString() ?? source;
    final version = package['version']?.toString() ?? 'versione sconosciuta';
    final pin = package['pinnedVersion']?.toString();
    final supportsPin = source.startsWith('npm:');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.extension_outlined, color: tokens.accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$version${pin == null ? '' : ' · pinned $pin'} · $source',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 10,
                      fontFamily: tokens.monoFontFamily,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Aggiorna $name',
              onPressed: _isWorkingWithPackage
                  ? null
                  : () => _updatePackage(package),
              icon: const Icon(Icons.system_update_alt, size: 18),
            ),
            if (supportsPin)
              IconButton(
                tooltip: 'Blocca versione $name',
                onPressed: _isWorkingWithPackage
                    ? null
                    : () => _pinPackage(package),
                icon: const Icon(Icons.push_pin_outlined, size: 18),
              ),
            IconButton(
              tooltip: 'Rimuovi $name',
              onPressed: _isWorkingWithPackage
                  ? null
                  : () => _removePackage(package),
              icon: Icon(Icons.delete_outline, size: 18, color: tokens.danger),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateTimeout(int newMinutes) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;

    setState(() {
      _workerIdleTimeoutMinutes = newMinutes;
      _configStatusMessage = 'Salvataggio in corso...';
    });

    try {
      await client.setDaemonConfig({'workerIdleTimeoutMs': newMinutes * 60000});
      if (mounted) {
        setState(() {
          _configStatusMessage = 'Timeout aggiornato con successo!';
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _configStatusMessage = null);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _configStatusMessage = 'Errore: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final endpointAsync = ref.watch(daemonEndpointProvider);
    final endpoint = endpointAsync.value;

    return Container(
      color: tokens.background,
      child: Column(
        children: [
          // Top Navigation Header
          Container(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Torna alla conversazione',
                      color: tokens.displayText,
                      onPressed: widget.onClose,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Impostazioni Pi-Crust',
                      style: TextStyle(
                        color: tokens.displayText,
                        fontSize: 28,
                        height: 1,
                        fontFamily: tokens.headingFontFamily,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: tokens.signalWarning,
                  labelColor: tokens.displayText,
                  unselectedLabelColor: tokens.displayText.withValues(
                    alpha: 0.72,
                  ),
                  labelStyle: TextStyle(
                    fontFamily: tokens.uiFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.7,
                  ),
                  tabs: const [
                    Tab(text: 'PI CLI'),
                    Tab(text: 'PACCHETTI'),
                    Tab(text: 'DAEMON'),
                    Tab(text: 'ASPETTO'),
                    Tab(text: 'PRIVACY'),
                    Tab(text: 'DIAGNOSTICA'),
                    Tab(text: 'AGGIORNAMENTI'),
                    Tab(text: 'ACCESSO REMOTO'),
                  ],
                ),
              ],
            ),
          ),

          // Tab views
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // -------------------------------------------------------------
                    // Tab 1: Pi CLI
                    // -------------------------------------------------------------
                    PiCliSection(
                      tokens: tokens,
                      onRecheck: () {
                        ref.invalidate(daemonEndpointProvider);
                      },
                    ),

                    // -------------------------------------------------------------
                    // Tab 2: Pacchetti Pi
                    // -------------------------------------------------------------
                    _packageList(tokens),

                    // -------------------------------------------------------------
                    // Tab 3: Daemon
                    // -------------------------------------------------------------
                    ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          'Stato del Daemon pi-agentd',
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Il daemon locale gestisce i processi Pi worker, il journal e il protocollo PCP/1.',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoCard(tokens, [
                          _buildInfoRow(
                            tokens,
                            'Porta HTTP/WS',
                            endpoint != null
                                ? '127.0.0.1:${endpoint.port}'
                                : 'In connessione...',
                          ),
                          _buildInfoRow(
                            tokens,
                            'Stato',
                            endpoint == null
                                ? 'Non connesso'
                                : 'Endpoint rilevato',
                          ),
                          _buildInfoRow(
                            tokens,
                            'Protocollo',
                            'PCP/1 (JSON testuale)',
                          ),
                        ]),
                        const SizedBox(height: 24),
                        Text(
                          'Timeout Inattività Worker (D9)',
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Dopo quanto tempo di inattività i processi Pi in idle vengono terminati per risparmiare risorse (i worker occupati non vengono mai terminati).',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _isLoadingConfig
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: tokens.accent,
                                  ),
                                ),
                              )
                            : Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tokens.surfaceElevated,
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusMd,
                                      ),
                                      border: Border.all(color: tokens.border),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<int>(
                                        borderRadius: BorderRadius.circular(
                                          tokens.radiusMd,
                                        ),
                                        value: _workerIdleTimeoutMinutes,
                                        dropdownColor: tokens.surfaceElevated,
                                        style: TextStyle(
                                          color: tokens.textPrimary,
                                          fontSize: 14,
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 0,
                                            child: Text('Mai (0 min)'),
                                          ),
                                          DropdownMenuItem(
                                            value: 5,
                                            child: Text('5 minuti'),
                                          ),
                                          DropdownMenuItem(
                                            value: 15,
                                            child: Text('15 minuti'),
                                          ),
                                          DropdownMenuItem(
                                            value: 30,
                                            child: Text('30 minuti (Default)'),
                                          ),
                                          DropdownMenuItem(
                                            value: 60,
                                            child: Text('1 ora (60 min)'),
                                          ),
                                          DropdownMenuItem(
                                            value: 120,
                                            child: Text('2 ore (120 min)'),
                                          ),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) _updateTimeout(val);
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  if (_configStatusMessage != null)
                                    Text(
                                      _configStatusMessage!,
                                      style: TextStyle(
                                        color: tokens.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Tooltip(
                            message: 'Riavvio disabilitato quando sono presenti worker attivi per proteggere le sessioni.',
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tokens.surfaceElevated,
                                foregroundColor: tokens.textMuted,
                              ),
                              icon: const Icon(Icons.restart_alt, size: 16),
                              label: const Text('Riavvia Daemon'),
                              onPressed: null, // Disabled when workers exist
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Notifiche di Sistema (macOS, Windows, Linux)',
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Invia notifiche di sistema quando l\'agente completa una risposta o richiede una scelta/conferma e l\'applicazione non è a fuoco.',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Notifiche di sistema quando l\'app non è a fuoco',
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                            value: ref.watch(notificationsEnabledProvider),
                            activeThumbColor: tokens.accent,
                            onChanged: (val) {
                              ref
                                  .read(notificationsEnabledProvider.notifier)
                                  .state = val;
                            },
                          ),
                        ),
                      ],
                    ),

                    // -------------------------------------------------------------
                    // Tab 4: Aspetto
                    // -------------------------------------------------------------
                    Consumer(
                      builder: (context, ref, _) {
                        final activeTheme = ref.watch(activeThemeSpecProvider);
                        final repo = ref.watch(themeRepositoryProvider);
                        final themes = repo.availableThemes;

                        return ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            Text(
                              'Personalizzazione Tema e UI',
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Pi-Crust supporta temi personalizzati definiti via file JSON in ~/.pi-crust/themes/.',
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Seleziona Tema: ',
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tokens.surfaceElevated,
                                    borderRadius: BorderRadius.circular(
                                      tokens.radiusMd,
                                    ),
                                    border: Border.all(color: tokens.border),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      isExpanded: true,
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusMd,
                                      ),
                                      value: activeTheme.id,
                                      dropdownColor: tokens.surfaceElevated,
                                      style: TextStyle(
                                        color: tokens.textPrimary,
                                        fontSize: 13,
                                        fontFamily: tokens.uiFontFamily,
                                      ),
                                      items: themes.map((t) {
                                        return DropdownMenuItem<String>(
                                          value: t.id,
                                          child: Text(
                                            '${t.name} (${t.variant})',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (newId) {
                                        if (newId != null) {
                                          ref
                                              .read(
                                                activeThemeSpecProvider
                                                    .notifier,
                                              )
                                              .setTheme(newId);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                key: const ValueKey('settings-import-theme-btn'),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: tokens.borderStrong),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      tokens.radiusSm,
                                    ),
                                  ),
                                ),
                                icon: Icon(
                                  Icons.file_upload_outlined,
                                  size: 16,
                                  color: tokens.accent,
                                ),
                                label: Text(
                                  'Importa tema JSON (VSCode / Pi-Crust)',
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: () async {
                                  try {
                                    final file = await openFile(
                                      acceptedTypeGroups: [
                                        const XTypeGroup(
                                          label: 'Tema JSON (*.json)',
                                          extensions: ['json'],
                                        ),
                                      ],
                                    );
                                    if (file == null || !context.mounted) return;
                                    final content = await file.readAsString();
                                    final importedSpec = await ref
                                        .read(activeThemeSpecProvider.notifier)
                                        .importThemeFromJson(content);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Tema "${importedSpec.name}" importato e attivato con successo!',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Errore durante l\'importazione del tema: $e',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildInfoCard(tokens, [
                              _buildInfoRow(
                                tokens,
                                'Tema attivo',
                                '${activeTheme.name} (v${activeTheme.version})',
                              ),
                              _buildInfoRow(
                                tokens,
                                'Densità layout',
                                'Confortevole (Default 1.0x)',
                              ),
                              _buildInfoRow(
                                tokens,
                                'Caratteri',
                                '${activeTheme.toTokens().uiFontFamily} (UI) · ${activeTheme.toTokens().monoFontFamily} (Codice)',
                              ),
                            ]),
                            if (activeTheme.diagnostics.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Diagnostica tema:',
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ...activeTheme.diagnostics.map(
                                (d) => Text(
                                  '• $d',
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),

                    // -------------------------------------------------------------
                    // Tab 5: Privacy (D16 — Zero Telemetry)
                    // -------------------------------------------------------------
                    ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              size: 24,
                              color: tokens.textPrimary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Informativa sulla Privacy e Tracciamento',
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: tokens.surfaceElevated,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Text(
                            'Pi-Crust non invia alcun dato di utilizzo a server remoti. I log restano sul tuo computer; puoi esportarli manualmente dalla sezione Diagnostica per condividerli con chi ti assiste.',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '• Zero telemetria, zero analytics di terze parti (nessun Google Analytics, Mixpanel o Sentry).\n'
                          '• Comunicazione locale confinata all\'interfaccia loopback 127.0.0.1 con token di autenticazione 256 bit.\n'
                          '• Nessuna modifica ai file di sessione o configurazioni originali di Pi in ~/.pi/.',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                            height: 1.8,
                          ),
                        ),
                      ],
                    ),

                    // -------------------------------------------------------------
                    // Tab 6: Diagnostica Locale & Export Bundle (D16)
                    // -------------------------------------------------------------
                    const DiagnosticsSection(),

                    // -------------------------------------------------------------
                    // Tab 7: Aggiornamenti Ufficiali GitHub
                    // -------------------------------------------------------------
                    const UpdatesSection(),

                    // -------------------------------------------------------------
                    // Tab 8: Accesso Remoto Sicuro
                    // -------------------------------------------------------------
                    const RemoteSection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(CrustTokens tokens, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow(CrustTokens tokens, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidget = Text(
            label,
            style: TextStyle(color: tokens.textSecondary, fontSize: 13),
          );
          final valueWidget = Text(
            value,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelWidget, const SizedBox(height: 4), valueWidget],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}
