import '../../domain/errors/user_facing_error.dart';
import '../../ui/frame_error_callout.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_errors.dart';
import '../../data/language/strings_settings.dart';
import '../../ui/frame_snack_bar.dart';

class RemoteSection extends ConsumerStatefulWidget {
  const RemoteSection({super.key});

  @override
  ConsumerState<RemoteSection> createState() => _RemoteSectionState();
}

class _RemoteSectionState extends ConsumerState<RemoteSection> {
  /// Keeps [e] as a mapped error for the callout. [title] is its context line.
  void _showError(Object e, {String? title}) {
    final strings = ref.read(appStringsProvider);
    _error = describeError(e, strings);
    _errorTitle = title ?? strings.remoteActionFailedTitle;
  }

  bool _isLoading = true;
  bool _isToggling = false;
  UserFacingError? _error;
  String? _errorTitle;

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
      _error = null;
      final remoteError = data['error'] as String?;
      if (remoteError != null) _showError(remoteError);

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
          _showError(e);
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
      _error = null;
    });

    try {
      final res = await client.installCloudflared();
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final installedPath = data['path'] as String? ?? '~/.piframe/bin/cloudflared';
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        final tokens = context.tokens;
        FrameSnackBar.show(
          context,
          message: strings.remoteCloudflaredReadySnackBar(installedPath),
          backgroundColor: tokens.success,
        );
      }
      await _fetchStatus();
    } catch (e) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        setState(() => _showError(e, title: strings.remoteInstallFailedTitle('cloudflared')));
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
      _error = null;
    });

    try {
      final res = await client.installTailscale();
      final data = res['data'] as Map<String, dynamic>? ?? res;
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        final tokens = context.tokens;
        FrameSnackBar.show(
          context,
          message: data['message'] as String? ?? strings.remoteTailscaleInstallDefaultToast,
          backgroundColor: tokens.accent,
        );
      }
      await _fetchStatus();
    } catch (e) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        setState(() => _showError(e, title: strings.remoteInstallFailedTitle('Tailscale')));
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
      _error = null;
    });

    try {
      final res = await client.setTailscaleHostname(text);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        final tokens = context.tokens;
        FrameSnackBar.show(
          context,
          message: strings.remoteTailscaleDomainUpdatedToast(data['domain']?.toString() ?? text),
          backgroundColor: tokens.success,
        );
      }
      await _fetchStatus();
    } catch (e) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        setState(() => _showError(e, title: strings.remoteRenameFailedTitle));
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
      final strings = ref.read(appStringsProvider);
      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.remoteTailscaleMissingDialogTitle),
          content: Text(strings.remoteTailscaleMissingDialogContent),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.cancel)),
            FilledButton.icon(
              icon: const Icon(Icons.download, size: 18),
              onPressed: () => Navigator.pop(ctx, true),
              label: Text(strings.remoteInstallTailscaleBtn),
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
      final strings = ref.read(appStringsProvider);
      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.remoteCloudflaredMissingDialogTitle),
          content: Text(strings.remoteCloudflaredMissingDialogContent),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.cancel)),
            FilledButton.icon(
              icon: const Icon(Icons.download, size: 18),
              onPressed: () => Navigator.pop(ctx, true),
              label: Text(strings.remoteInstallAndStartBtn),
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
      _error = null;
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
        setState(() => _showError(e));
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
      if (mounted) setState(() => _showError(e));
    }
  }

  Future<void> _revokeDevice(String deviceId, String name) async {
    final strings = ref.read(appStringsProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.remoteRevokeDeviceDialogTitle),
        content: Text(strings.remoteRevokeDeviceDialogContent(name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.remoteRevokeBtn),
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
      if (mounted) setState(() => _showError(e));
    }
  }

  Future<void> _revokeAllDevices() async {
    final strings = ref.read(appStringsProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.remoteRevokeAllDialogTitle),
        content: Text(strings.remoteRevokeAllDialogContent),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.remoteRevokeAllBtn),
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
      if (mounted) setState(() => _showError(e));
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
      if (mounted) setState(() => _showError(e));
    }
  }

  Future<void> _changeDeviceMode(String deviceId, String currentMode, String newMode, String deviceName) async {
    if (newMode == currentMode) return;

    if (newMode == 'control') {
      final strings = ref.read(appStringsProvider);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.remoteControlConfirmTitle),
          content: Text(strings.remoteControlConfirmContent(deviceName)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(strings.remoteGrantControlBtn),
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
      if (mounted) setState(() => _showError(e));
    }
  }

  String _formatExpires(int? expiresAt, AppStrings strings) {
    if (expiresAt == null) return '';
    final diff = expiresAt - DateTime.now().millisecondsSinceEpoch;
    if (diff <= 0) return strings.remotePairExpired;
    final mins = diff ~/ 60000;
    final secs = (diff % 60000) ~/ 1000;
    return strings.remotePairExpiresIn(mins, secs.toString().padLeft(2, '0'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    // A missing optional binary is informational while remote access is off,
    // and only needs attention once remote access is on.
    final missingBinaryTone = _enabled ? tokens.warning : tokens.info;

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
                  Text(strings.remoteTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    strings.remoteSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FrameErrorCallout(
              keyPrefix: 'remote',
              title: _errorTitle ?? strings.remoteActionFailedTitle,
              error: _error!,
              strings: strings,
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
                          Text(strings.remoteEnableTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          _buildStatusBadge(colorScheme, tokens, strings),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _enabled
                            ? strings.remoteEnabledDesc
                            : strings.remoteDisabledDesc,
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
                  Text(strings.remotePairSmartphoneTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
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
                          Text(strings.remotePairStep1, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(strings.remotePairStep1Desc, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 12),

                          if (_pairingExpiresAt != null) ...[
                            Row(
                              children: [
                                Icon(Icons.timer_outlined, size: 16, color: colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  _formatExpires(_pairingExpiresAt, strings),
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
                                label: Text(strings.remoteNewQrBtn),
                                onPressed: _generateNewPairing,
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.copy, size: 16),
                                label: Text(strings.remoteCopyPairLinkBtn),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _pairingUrl ?? _url!));
                                  FrameSnackBar.show(
                                    context,
                                    message: strings.remotePairLinkCopiedSnackBar,
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.open_in_browser, size: 20),
                                tooltip: strings.remoteOpenInBrowserTooltip,
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
                      Text(strings.remotePublicUrlLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
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
                  Text(strings.remoteDefaultModeTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    strings.remoteDefaultModeSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'view',
                        label: Text(strings.remoteSegmentView),
                        icon: const Icon(Icons.visibility),
                      ),
                      ButtonSegment(
                        value: 'control',
                        label: Text(strings.remoteSegmentControl),
                        icon: const Icon(Icons.settings_remote),
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
                        ? strings.remoteModeViewExplanation
                        : strings.remoteModeControlExplanation,
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
                      Text(strings.remoteAuthorizedDevicesTitle(_devices.length), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (_devices.isNotEmpty)
                        TextButton.icon(
                          icon: Icon(Icons.delete_forever, size: 16, color: colorScheme.error),
                          label: Text(strings.remoteRevokeAllBtn, style: TextStyle(color: colorScheme.error, fontSize: 12)),
                          onPressed: _revokeAllDevices,
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  if (_devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        strings.remoteNoDevicesAuthorized,
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    )
                  else
                    ..._devices.map((dev) {
                      final name = dev['name'] as String? ?? strings.remoteUnknownDevice;
                      final deviceId = dev['deviceId'] as String? ?? '';
                      final mode = dev['mode'] as String? ?? 'view';
                      final ip = dev['remoteIp'] as String? ?? strings.remoteLocalIp;
                      final lastUsed = dev['lastUsedAt'] as int?;
                      final expiresAt = dev['expiresAt'] as int?;
                      final lastStr = lastUsed != null
                          ? DateTime.fromMillisecondsSinceEpoch(lastUsed).toLocal().toString().split('.')[0]
                          : strings.remoteNeverUsed;
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
                                    strings.remoteDeviceInfoLine(ip, lastStr, expiresStr),
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
                              child: Text(strings.remoteRevokeBtn, style: const TextStyle(fontSize: 12)),
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
                Text(strings.remoteProviderConfigTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
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
                      items: [
                        DropdownMenuItem(
                          value: 'tailscale',
                          child: Text(strings.remoteProviderTailscale),
                        ),
                        DropdownMenuItem(
                          value: 'cloudflared',
                          child: Text(strings.remoteProviderCloudflared),
                        ),
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text(strings.remoteProviderCustom),
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
                        color: missingBinaryTone.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: missingBinaryTone.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: missingBinaryTone, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  strings.remoteTailscaleNotInstalledTitle,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: missingBinaryTone),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            strings.remoteTailscaleNotInstalledDesc,
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
                            label: Text(_isInstallingTailscale ? strings.remoteTailscaleInstallingBtn : strings.remoteTailscaleInstallAutoBtn),
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
                          Expanded(
                            child: Text(
                              strings.remoteTailscaleNotRunning,
                              style: const TextStyle(fontSize: 12),
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
                                  strings.remoteTailscaleActiveTitle,
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
                              strings.remoteTailscalePermanentAddress(_tailscaleDomain!),
                              style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            strings.remoteTailscaleCustomizeHostname,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _tailscaleHostnameController,
                                  decoration: InputDecoration(
                                    labelText: strings.remoteTailscaleHostnameLabel,
                                    border: const OutlineInputBorder(),
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
                                    : Text(strings.remoteTailscaleSaveNameBtn),
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
                                  strings.remoteCloudflaredDetectedTitle,
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
                                  strings.remoteCloudflaredNotFoundTitle,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            strings.remoteCloudflaredNotFoundDesc,
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
                            label: Text(_isInstallingCloudflared ? strings.remoteCloudflaredInstallingBtn : strings.remoteCloudflaredInstallAutoBtn),
                            onPressed: _isInstallingCloudflared ? null : _installCloudflared,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            strings.remoteCloudflaredInstallNote,
                            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],

                if (_localPort != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    strings.remoteDedicatedListenerPort(_localPort!),
                    style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, color: colorScheme.primary),
                  ),
                ],

                if (_tunnelProvider == 'custom') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _customUrlController,
                    decoration: InputDecoration(
                      labelText: strings.remoteCustomHttpsUrlLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _customCommandController,
                    decoration: InputDecoration(
                      labelText: strings.remoteCustomCommandLabel,
                      border: const OutlineInputBorder(),
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

  Widget _buildStatusBadge(ColorScheme colorScheme, FrameTokens tokens, AppStrings strings) {
    Color bg;
    Color fg;
    String label;

    switch (_state) {
      case 'running':
        bg = tokens.success.withValues(alpha: 0.2);
        fg = tokens.success;
        label = strings.remoteStatusActive;
        break;
      case 'starting':
        bg = tokens.warning.withValues(alpha: 0.2);
        fg = tokens.warning;
        label = strings.remoteStatusStarting;
        break;
      case 'error':
        bg = tokens.danger.withValues(alpha: 0.2);
        fg = tokens.danger;
        label = strings.remoteStatusError;
        break;
      default:
        bg = tokens.textMuted.withValues(alpha: 0.1);
        fg = tokens.textMuted;
        label = strings.remoteStatusDisabled;
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
