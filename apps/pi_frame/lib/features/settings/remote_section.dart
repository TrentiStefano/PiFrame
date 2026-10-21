import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/daemon/daemon_providers.dart';

class RemoteSection extends ConsumerStatefulWidget {
  const RemoteSection({super.key});

  @override
  ConsumerState<RemoteSection> createState() => _RemoteSectionState();
}

class _RemoteSectionState extends ConsumerState<RemoteSection> {
  bool _isLoading = true;
  bool _isToggling = false;
  String? _errorMessage;

  bool _enabled = false;
  String _state = 'stopped';
  String? _url;
  String _tunnelProvider = 'cloudflared';
  int? _localPort;
  String? _pairingUrl;
  int? _pairingExpiresAt;
  String _defaultMode = 'view';
  bool _cloudflaredInstalled = false;
  String? _cloudflaredPath;
  bool _isInstallingCloudflared = false;

  bool _tailscaleInstalled = false;
  bool _tailscaleRunning = false;
  String? _tailscaleHostname;
  String? _tailscaleDomain;
  bool _isInstallingTailscale = false;
  bool _isSavingTailscaleHostname = false;
  final _tailscaleHostnameController = TextEditingController();

  List<Map<String, dynamic>> _devices = [];

  Timer? _countdownTimer;
  StreamSubscription? _eventSub;

  final _customUrlController = TextEditingController();
  final _customCommandController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _subscribeEvents();
  }

  void _startCountdownIfNeeded() {
    if (_countdownTimer != null || _pairingExpiresAt == null) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_pairingExpiresAt != null) {
        setState(() {});
      } else {
        _countdownTimer?.cancel();
        _countdownTimer = null;
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _eventSub?.cancel();
    _customUrlController.dispose();
    _customCommandController.dispose();
    _tailscaleHostnameController.dispose();
    super.dispose();
  }

  void _subscribeEvents() {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    _eventSub = client.events('@daemon').listen((event) {
      if (event.type == 'remote.statusChanged') {
        _applyStatusData(event.payload);
      }
    });
  }

  void _applyStatusData(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _enabled = data['enabled'] as bool? ?? false;
      _state = data['state'] as String? ?? 'stopped';
      _url = data['url'] as String?;
      _tunnelProvider = data['tunnelProvider'] as String? ?? 'cloudflared';
      _cloudflaredInstalled = data['cloudflaredInstalled'] as bool? ?? false;
      _cloudflaredPath = data['cloudflaredPath'] as String?;

      final ts = data['tailscale'] as Map<String, dynamic>?;
      if (ts != null) {
        _tailscaleInstalled = ts['installed'] as bool? ?? false;
        _tailscaleRunning = ts['running'] as bool? ?? false;
        _tailscaleHostname = ts['hostname'] as String?;
        _tailscaleDomain = ts['domain'] as String?;
        if (_tailscaleHostname != null && _tailscaleHostnameController.text.isEmpty) {
          _tailscaleHostnameController.text = _tailscaleHostname!;
        }
      }

      _localPort = data['localPort'] as int?;
      _errorMessage = data['error'] as String?;

      final pairing = data['pairingPending'] as Map<String, dynamic>?;
      _pairingUrl = pairing?['url'] as String?;
      _pairingExpiresAt = pairing?['expiresAt'] as int?;
      _startCountdownIfNeeded();

      final options = data['options'] as Map<String, dynamic>?;
      if (options != null) {
        _defaultMode = options['defaultMode'] as String? ?? 'view';
      }

      final devs = data['devices'] as List?;
      _devices = devs != null
          ? devs.map((d) => Map<String, dynamic>.from(d as Map)).toList()
          : [];
      _isLoading = false;
    });
  }

  Future<void> _fetchStatus() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final res = await client.getRemoteStatus();
      final data = res['data'] as Map<String, dynamic>? ?? res;
      _applyStatusData(data);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _installCloudflared() async {
    final client = ref.read(pcpClientProvider);
    if (client == null || _isInstallingCloudflared) return;

    setState(() {
      _isInstallingCloudflared = true;
      _errorMessage = null;
    });

    try {
      final res = await client.installCloudflared();
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final installedPath = data['path'] as String? ?? '~/.piframe/bin/cloudflared';
      if (mounted) {
        final tokens = context.tokens;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('cloudflared scaricato e pronto in $installedPath!'),
            backgroundColor: tokens.success,
          ),
        );
      }
      await _fetchStatus();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Errore durante l\'installazione di cloudflared: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isInstallingCloudflared = false);
      }
    }
  }

  Future<void> _installTailscale() async {
    final client = ref.read(pcpClientProvider);
    if (client == null || _isInstallingTailscale) return;

    setState(() {
      _isInstallingTailscale = true;
      _errorMessage = null;
    });

    try {
      final res = await client.installTailscale();
      final data = res['data'] as Map<String, dynamic>? ?? res;
      if (mounted) {
        final tokens = context.tokens;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] as String? ?? 'Installazione di Tailscale avviata! Conferma il prompt di Windows.'),
            backgroundColor: tokens.accent,
          ),
        );
      }
      await _fetchStatus();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Errore durante l\'installazione di Tailscale: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isInstallingTailscale = false);
      }
    }
  }

  Future<void> _saveTailscaleHostname() async {
    final client = ref.read(pcpClientProvider);
    final text = _tailscaleHostnameController.text.trim();
    if (client == null || text.isEmpty || _isSavingTailscaleHostname) return;

    setState(() {
      _isSavingTailscaleHostname = true;
      _errorMessage = null;
    });

    try {
      final res = await client.setTailscaleHostname(text);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      if (mounted) {
        final tokens = context.tokens;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nome host Tailscale aggiornato! Nuovo dominio: ${data['domain'] ?? text}'),
            backgroundColor: tokens.success,
          ),
        );
      }
      await _fetchStatus();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Errore durante la ridenominazione: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingTailscaleHostname = false);
      }
    }
  }

  Future<void> _toggleRemote(bool enable) async {
    final client = ref.read(pcpClientProvider);
    if (client == null || _isToggling) return;

    if (enable && _tunnelProvider == 'tailscale' && !_tailscaleInstalled) {
      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tailscale non installato'),
          content: const Text(
            'Per utilizzare il tunnel permanente Tailscale è necessario installare Tailscale sul PC.\n\n'
            'Vuoi avviare l\'installazione automatica adesso?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton.icon(
              icon: const Icon(Icons.download, size: 18),
              onPressed: () => Navigator.pop(ctx, true),
              label: const Text('Installa Tailscale'),
            ),
          ],
        ),
      );
      if (shouldInstall == true) {
        await _installTailscale();
      }
      return;
    }

    if (enable && _tunnelProvider == 'cloudflared' && !_cloudflaredInstalled) {
      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('cloudflared richiesto'),
          content: const Text(
            'Per avviare la connessione remota con Cloudflare è necessario l\'eseguibile ufficiale cloudflared.\n\n'
            'Vuoi scaricarlo e installarlo automaticamente in ~/.piframe/bin/? Non richiede permessi di amministratore.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton.icon(
              icon: const Icon(Icons.download, size: 18),
              onPressed: () => Navigator.pop(ctx, true),
              label: const Text('Installa e Avvia'),
            ),
          ],
        ),
      );
      if (shouldInstall == true) {
        await _installCloudflared();
        if (!_cloudflaredInstalled) return;
      } else {
        return;
      }
    }

    setState(() {
      _isToggling = true;
      _errorMessage = null;
    });

    try {
      if (enable) {
        final res = await client.startRemoteTunnel(
          tunnelProvider: _tunnelProvider,
          customUrl: _tunnelProvider == 'tailscale'
              ? (_tailscaleDomain != null ? 'https://$_tailscaleDomain' : null)
              : (_customUrlController.text.trim().isEmpty ? null : _customUrlController.text.trim()),
          customCommand: _customCommandController.text.trim().isEmpty ? null : _customCommandController.text.trim(),
        );
        final data = res['data'] as Map<String, dynamic>? ?? res;
        _applyStatusData(data);
      } else {
        final res = await client.stopRemoteTunnel();
        final data = res['data'] as Map<String, dynamic>? ?? res;
        _applyStatusData(data);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isToggling = false);
      }
    }
  }

  Future<void> _generateNewPairing() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      final res = await client.generateRemotePairing(ttlMs: 5 * 60 * 1000);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      if (mounted) {
        setState(() {
          _pairingUrl = data['url'] as String?;
          _pairingExpiresAt = data['expiresAt'] as int?;
          _startCountdownIfNeeded();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _revokeDevice(String deviceId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoca Dispositivo'),
        content: Text('Vuoi revocare l\'accesso a "$name"? La connessione verrà terminata immediatamente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoca'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      await client.revokeRemoteDevice(deviceId);
      await _fetchStatus();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _revokeAllDevices() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoca Tutti i Dispositivi'),
        content: const Text('Tutte le sessioni remote verranno disconnesse e i token invalidati immediatamente. Continuare?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoca Tutti'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      await client.revokeAllRemoteDevices();
      await _fetchStatus();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _updateDefaultMode(String mode) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      final res = await client.setRemoteOptions(defaultMode: mode);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      _applyStatusData(data);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _changeDeviceMode(String deviceId, String currentMode, String newMode, String deviceName) async {
    if (newMode == currentMode) return;

    if (newMode == 'control') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Conferma Modalità Controllo'),
          content: Text(
            'Stai concedendo i permessi di CONTROLLO COMPLETO a "$deviceName".\n\n'
            'Questo dispositivo potrà inviare prompt ed eseguire comandi sul tuo computer con gli stessi privilegi del tuo utente.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Concedi Controllo'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      await client.setRemoteDeviceMode(deviceId: deviceId, mode: newMode);
      await _fetchStatus();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  String _formatExpires(int? expiresAt) {
    if (expiresAt == null) return '';
    final diff = expiresAt - DateTime.now().millisecondsSinceEpoch;
    if (diff <= 0) return 'Scaduto';
    final mins = diff ~/ 60000;
    final secs = (diff % 60000) ~/ 1000;
    return 'Scade tra ${mins}m ${secs.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.tokens;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isRunning = _state == 'running';
    final isStarting = _state == 'starting' || _isToggling;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Title & Description
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.phonelink_ring, size: 28, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connessione Remota Sicura', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Accedi al tuo Pi dallo smartphone o dal browser in mobilità. Tunnel crittografato, associazione one-time via QR code con URL fragment (#pair=...), token per-dispositivo con scadenza e controllo granulare dei permessi (view o control).',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        if (_errorMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!, style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 13))),
              ],
            ),
          ),

        // Main Toggle Card
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Abilita Accesso Remoto', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          _buildStatusBadge(colorScheme, tokens),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _enabled
                            ? 'Il listener remoto dedicato è attivo. Inquadra il QR code per associare un dispositivo.'
                            : 'Disattivato (opt-in). Nessuna connessione esterna è accettata.',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: isStarting ? null : (val) => _toggleRemote(val),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Active Remote Connection Details
        if (_enabled && isRunning && _url != null) ...[
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Associa il tuo Smartphone', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 620;
                      final qrData = _pairingUrl ?? _url!;
                      final qrWidget = Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: tokens.overlay.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: qrData,
                          version: QrVersions.auto,
                          size: 160.0,
                          backgroundColor: tokens.surfaceElevated,
                          dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: tokens.textPrimary,
                          ),
                          eyeStyle: QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: tokens.textPrimary,
                          ),
                        ),
                      );

                      final infoWidget = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('1. Inquadra il QR con la fotocamera del telefono', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Aprirà la webapp PiFrame con associazione sicura monouso via fragment crittografico.', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 12),

                          if (_pairingExpiresAt != null) ...[
                            Row(
                              children: [
                                Icon(Icons.timer_outlined, size: 16, color: colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  _formatExpires(_pairingExpiresAt),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],

                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Nuovo codice QR'),
                                onPressed: _generateNewPairing,
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copia Link di Associazione'),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _pairingUrl ?? _url!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Link di associazione copiato negli appunti!')),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.open_in_browser, size: 20),
                                tooltip: 'Apri nel browser',
                                onPressed: () => launchUrl(Uri.parse(_url!)),
                              ),
                            ],
                          ),
                        ],
                      );

                      if (isCompact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(child: qrWidget),
                            const SizedBox(height: 16),
                            infoWidget,
                          ],
                        );
                      } else {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            qrWidget,
                            const SizedBox(width: 24),
                            Expanded(child: infoWidget),
                          ],
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 16),
                  Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Icon(Icons.link, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('URL Pubblico: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                      Expanded(
                        child: SelectableText(
                          _url!,
                          style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, color: colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Security Guardrails & Default Mode Card
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Modalità Predefinita per Nuovi Dispositivi', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    'I nuovi dispositivi associati ricevono questa modalità. Puoi modificarla per singolo dispositivo nella lista sottostante.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'view',
                        label: Text('Visualizzazione (View)'),
                        icon: Icon(Icons.visibility),
                      ),
                      ButtonSegment(
                        value: 'control',
                        label: Text('Controllo (Control)'),
                        icon: Icon(Icons.settings_remote),
                      ),
                    ],
                    selected: {_defaultMode},
                    onSelectionChanged: (set) {
                      if (set.isNotEmpty) _updateDefaultMode(set.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _defaultMode == 'view'
                        ? 'La modalità View consente di consultare sessioni, log e file in sola lettura, con possibilità di abortire l\'agente in caso di emergenza. Nessun prompt o modifica consentita.'
                        : 'La modalità Control consente di inviare messaggi, avviare sessioni ed eseguire azioni complete tramite l\'agente.',
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Paired Devices Management
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Dispositivi Autorizzati (${_devices.length})', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (_devices.isNotEmpty)
                        TextButton.icon(
                          icon: Icon(Icons.delete_forever, size: 16, color: colorScheme.error),
                          label: Text('Revoca Tutti', style: TextStyle(color: colorScheme.error, fontSize: 12)),
                          onPressed: _revokeAllDevices,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Nessun dispositivo autorizzato. Inquadra il QR code per associare il tuo smartphone.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    )
                  else
                    ..._devices.map((dev) {
                      final name = dev['name'] as String? ?? 'Dispositivo Sconosciuto';
                      final deviceId = dev['deviceId'] as String? ?? '';
                      final mode = dev['mode'] as String? ?? 'view';
                      final ip = dev['remoteIp'] as String? ?? 'Locale';
                      final lastUsed = dev['lastUsedAt'] as int?;
                      final expiresAt = dev['expiresAt'] as int?;
                      final lastStr = lastUsed != null
                          ? DateTime.fromMillisecondsSinceEpoch(lastUsed).toLocal().toString().split('.')[0]
                          : 'Mai';
                      final expiresStr = expiresAt != null
                          ? DateTime.fromMillisecondsSinceEpoch(expiresAt).toLocal().toString().split(' ')[0]
                          : '-';

                      final isControl = mode == 'control';

                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              name.contains('iOS') || name.contains('Android') ? Icons.smartphone : Icons.devices,
                              color: colorScheme.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: isControl
                                              ? tokens.accent.withValues(alpha: 0.2)
                                              : tokens.info.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isControl ? 'CONTROL' : 'VIEW',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isControl ? tokens.accent : tokens.info,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'IP: $ip • Ultima attività: $lastStr • Scade: $expiresStr',
                                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            DropdownButton<String>(
                              value: mode,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(value: 'view', child: Text('View', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'control', child: Text('Control', style: TextStyle(fontSize: 12))),
                              ],
                              onChanged: (newMode) {
                                if (newMode != null) {
                                  _changeDeviceMode(deviceId, mode, newMode, name);
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.error,
                                side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _revokeDevice(deviceId, name),
                              child: const Text('Revoca', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],

        // Provider configuration
        const SizedBox(height: 20),
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Configurazione Provider Tunnel', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _tunnelProvider,
                      items: const [
                        DropdownMenuItem(
                          value: 'tailscale',
                          child: Text('Tailscale (Consigliato: Permanente, Privato e Sicuro)'),
                        ),
                        DropdownMenuItem(
                          value: 'cloudflared',
                          child: Text('Cloudflare Quick Tunnel (Temporaneo, nessun account)'),
                        ),
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text('Altro Tunnel Personalizzato / Reverse Proxy'),
                        ),
                      ],
                      onChanged: _enabled ? null : (val) => setState(() => _tunnelProvider = val!),
                    ),
                  ),
                ),

                if (_tunnelProvider == 'tailscale') ...[
                  const SizedBox(height: 12),
                  if (!_tailscaleInstalled)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tailscale non è installato su questo computer',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tailscale crea una rete privata sicura Mesh (WireGuard) tra i tuoi dispositivi con certificato HTTPS e nome di dominio fisso permanente.',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            icon: _isInstallingTailscale
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tokens.accentContrast,
                                    ),
                                  )
                                : const Icon(Icons.download, size: 18),
                            label: Text(_isInstallingTailscale ? 'Avvio installazione...' : 'Installa Tailscale automaticamente'),
                            onPressed: _isInstallingTailscale ? null : _installTailscale,
                          ),
                        ],
                      ),
                    )
                  else if (!_tailscaleRunning)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tokens.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tokens.warning.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: tokens.warning, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Tailscale è installato ma non è connesso. Apri l\'app Tailscale ed effettua il login per attivare la rete.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tokens.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tokens.info.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.verified_user, color: tokens.info, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tailscale è attivo e connesso',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: tokens.info,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_tailscaleDomain != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Indirizzo permanente: https://$_tailscaleDomain',
                              style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            'Personalizza il nome host della macchina:',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _tailscaleHostnameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Nome host Tailscale (es. pi-frame)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton(
                                onPressed: _isSavingTailscaleHostname ? null : _saveTailscaleHostname,
                                child: _isSavingTailscaleHostname
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: tokens.accentContrast,
                                        ),
                                      )
                                    : const Text('Salva nome'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],

                if (_tunnelProvider == 'cloudflared') ...[
                  const SizedBox(height: 12),
                  if (_cloudflaredInstalled)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: tokens.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tokens.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: tokens.success, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'cloudflared rilevato e pronto all\'uso',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: tokens.success,
                                  ),
                                ),
                                if (_cloudflaredPath != null)
                                  Text(
                                    _cloudflaredPath!,
                                    style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 11, color: colorScheme.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Eseguibile cloudflared non trovato',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Per utilizzare i Quick Tunnel di Cloudflare è necessario l\'eseguibile ufficiale open-source di Cloudflare.',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            icon: _isInstallingCloudflared
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tokens.accentContrast,
                                    ),
                                  )
                                : const Icon(Icons.download, size: 18),
                            label: Text(_isInstallingCloudflared ? 'Download e installazione in corso...' : 'Installa cloudflared automaticamente'),
                            onPressed: _isInstallingCloudflared ? null : _installCloudflared,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Verrà scaricato in ~/.piframe/bin/cloudflared senza richiedere permessi di amministratore o riavvii.',
                            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],

                if (_localPort != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Porta del listener remoto dedicato: $_localPort (127.0.0.1:$_localPort)',
                    style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, color: colorScheme.primary),
                  ),
                ],

                if (_tunnelProvider == 'custom') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _customUrlController,
                    decoration: const InputDecoration(
                      labelText: 'URL Pubblico HTTPS (es. https://my-node.ts.net)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _customCommandController,
                    decoration: const InputDecoration(
                      labelText: 'Comando tunnel (eseguito senza shell, "\$PORT" sostituito con la porta listener)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(ColorScheme colorScheme, FrameTokens tokens) {
    Color bg;
    Color fg;
    String label;

    switch (_state) {
      case 'running':
        bg = tokens.success.withValues(alpha: 0.2);
        fg = tokens.success;
        label = 'ATTIVO';
        break;
      case 'starting':
        bg = tokens.warning.withValues(alpha: 0.2);
        fg = tokens.warning;
        label = 'AVVIO...';
        break;
      case 'error':
        bg = tokens.danger.withValues(alpha: 0.2);
        fg = tokens.danger;
        label = 'ERRORE';
        break;
      default:
        bg = tokens.textMuted.withValues(alpha: 0.1);
        fg = tokens.textMuted;
        label = 'DISATTIVATO';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
