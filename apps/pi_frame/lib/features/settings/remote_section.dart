import '../../domain/errors/user_facing_error.dart';
import '../../data/errors/user_facing_error_mapping.dart';
import '../../ui/frame_activity_indicator.dart';
import '../../ui/frame_callout.dart';
import '../../ui/frame_dialog.dart';
import '../../ui/frame_error_callout.dart';
import '../../ui/frame_section.dart';
import '../../ui/frame_status_tag.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_errors.dart';
import '../../data/language/strings_settings.dart';
import '../../data/platform/link_service.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/precision.dart';

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
      _devices = devs != null ? devs.map((d) => Map<String, dynamic>.from(d as Map)).toList() : [];
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
      final shouldInstall = await showFrameDialog<bool>(
        context: context,
        dialog: FrameDialog<bool>(
          title: strings.remoteTailscaleMissingDialogTitle,
          body: Text(strings.remoteTailscaleMissingDialogContent),
          actions: [
            FrameDialogAction(label: strings.cancel, role: FrameDialogActionRole.cancel, value: false),
            FrameDialogAction(
              label: strings.remoteInstallTailscaleBtn,
              role: FrameDialogActionRole.primary,
              value: true,
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
      final shouldInstall = await showFrameDialog<bool>(
        context: context,
        dialog: FrameDialog<bool>(
          title: strings.remoteCloudflaredMissingDialogTitle,
          body: Text(strings.remoteCloudflaredMissingDialogContent),
          actions: [
            FrameDialogAction(label: strings.cancel, role: FrameDialogActionRole.cancel, value: false),
            FrameDialogAction(
              label: strings.remoteInstallAndStartBtn,
              role: FrameDialogActionRole.primary,
              value: true,
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
    final confirm = await showFrameDialog<bool>(
      context: context,
      dialog: FrameDialog<bool>(
        title: strings.remoteRevokeDeviceDialogTitle,
        body: Text(strings.remoteRevokeDeviceDialogContent(name)),
        actions: [
          FrameDialogAction(label: strings.cancel, role: FrameDialogActionRole.cancel, value: false),
          FrameDialogAction(label: strings.remoteRevokeBtn, role: FrameDialogActionRole.destructive, value: true),
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
    final confirm = await showFrameDialog<bool>(
      context: context,
      dialog: FrameDialog<bool>(
        title: strings.remoteRevokeAllDialogTitle,
        body: Text(strings.remoteRevokeAllDialogContent),
        actions: [
          FrameDialogAction(label: strings.cancel, role: FrameDialogActionRole.cancel, value: false),
          FrameDialogAction(label: strings.remoteRevokeAllBtn, role: FrameDialogActionRole.destructive, value: true),
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
      final confirmed = await showFrameDialog<bool>(
        context: context,
        dialog: FrameDialog<bool>(
          title: strings.remoteControlConfirmTitle,
          body: Text(strings.remoteControlConfirmContent(deviceName)),
          actions: [
            FrameDialogAction(label: strings.cancel, role: FrameDialogActionRole.cancel, value: false),
            FrameDialogAction(
              label: strings.remoteGrantControlBtn,
              role: FrameDialogActionRole.destructive,
              value: true,
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
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);
    // A missing optional binary is informational while remote access is off,
    // and only needs attention once remote access is on.
    final missingBinaryTone = _enabled ? FrameCalloutTone.warning : FrameCalloutTone.info;

    if (_isLoading) {
      return Center(
        child: FrameActivityIndicator(size: FrameSize.iconLg, strokeWidth: 2, color: tokens.accent),
      );
    }

    final isRunning = _state == 'running';
    final isStarting = _state == 'starting' || _isToggling;

    return ListView(
      padding: const EdgeInsets.all(FrameSpace.x6),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.phonelink_ring_outlined, size: FrameSize.iconLg, color: tokens.accent),
            const SizedBox(width: FrameSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.remoteTitle, style: text.title.copyWith(color: tokens.textPrimary)),
                  const SizedBox(height: FrameSpace.x1),
                  Text(strings.remoteSubtitle, style: text.body.copyWith(color: tokens.textSecondary)),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: FrameSpace.x6),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: FrameSpace.x4),
            child: FrameErrorCallout(
              keyPrefix: 'remote',
              title: _errorTitle ?? strings.remoteActionFailedTitle,
              error: _error!,
              strings: strings,
            ),
          ),

        // Main toggle
        FrameSection(
          title: strings.remoteEnableTitle,
          description: _enabled ? strings.remoteEnabledDesc : strings.remoteDisabledDesc,
          child: Row(
            children: [
              _buildStatusBadge(colorScheme, tokens, strings),
              const Spacer(),
              Switch(value: _enabled, onChanged: isStarting ? null : (val) => _toggleRemote(val)),
            ],
          ),
        ),

        const SizedBox(height: FrameSpace.x6),

        // Active remote connection details
        if (_enabled && isRunning && _url != null) ...[
          FrameSection(
            title: strings.remotePairSmartphoneTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 620;
                    final qrData = _pairingUrl ?? _url!;
                    final qrWidget = Container(
                      padding: const EdgeInsets.all(FrameSpace.x3),
                      decoration: BoxDecoration(
                        color: tokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(tokens.radiusMd),
                        border: Border.all(color: tokens.border),
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
                        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: tokens.textPrimary),
                      ),
                    );

                    final infoWidget = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.remotePairStep1,
                          style: text.bodyLarge.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: FrameSpace.x1),
                        Text(strings.remotePairStep1Desc, style: text.body.copyWith(color: tokens.textSecondary)),
                        const SizedBox(height: FrameSpace.x3),

                        if (_pairingExpiresAt != null) ...[
                          Row(
                            children: [
                              Icon(Icons.timer_outlined, size: FrameSize.icon, color: tokens.accent),
                              const SizedBox(width: FrameSpace.x2),
                              Text(
                                _formatExpires(_pairingExpiresAt, strings),
                                style: text.label.copyWith(color: tokens.accent, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: FrameSpace.x3),
                        ],

                        Wrap(
                          spacing: FrameSpace.x2,
                          runSpacing: FrameSpace.x2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            PressFeedback(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.refresh_outlined, size: FrameSize.icon),
                                label: Text(strings.remoteNewQrBtn),
                                onPressed: _generateNewPairing,
                              ),
                            ),
                            PressFeedback(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.copy_outlined, size: FrameSize.icon),
                                label: Text(strings.remoteCopyPairLinkBtn),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _pairingUrl ?? _url!));
                                  FrameSnackBar.show(context, message: strings.remotePairLinkCopiedSnackBar);
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.open_in_browser_outlined, size: FrameSize.iconLg),
                              tooltip: strings.remoteOpenInBrowserTooltip,
                              onPressed: () => ref.read(linkServiceProvider).openExternal(Uri.parse(_url!)),
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
                          const SizedBox(height: FrameSpace.x4),
                          infoWidget,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        qrWidget,
                        const SizedBox(width: FrameSpace.x6),
                        Expanded(child: infoWidget),
                      ],
                    );
                  },
                ),

                const SizedBox(height: FrameSpace.x4),
                Divider(color: tokens.border),
                const SizedBox(height: FrameSpace.x2),

                Row(
                  children: [
                    Icon(Icons.link_outlined, size: FrameSize.icon, color: tokens.accent),
                    const SizedBox(width: FrameSpace.x2),
                    Text(
                      strings.remotePublicUrlLabel,
                      style: text.label.copyWith(color: tokens.textSecondary, fontWeight: FontWeight.w600),
                    ),
                    Expanded(
                      child: SelectableText(_url!, style: text.mono.copyWith(color: tokens.accent)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: FrameSpace.x6),
        ],

        // Security guardrails and default mode
        FrameSection(
          title: strings.remoteDefaultModeTitle,
          description: strings.remoteDefaultModeSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'view',
                    label: Text(strings.remoteSegmentView),
                    icon: const Icon(Icons.visibility_outlined),
                  ),
                  ButtonSegment(
                    value: 'control',
                    label: Text(strings.remoteSegmentControl),
                    icon: const Icon(Icons.settings_remote_outlined),
                  ),
                ],
                selected: {_defaultMode},
                onSelectionChanged: (set) {
                  if (set.isNotEmpty) _updateDefaultMode(set.first);
                },
              ),
              const SizedBox(height: FrameSpace.x2),
              Text(
                _defaultMode == 'view' ? strings.remoteModeViewExplanation : strings.remoteModeControlExplanation,
                style: text.caption.copyWith(fontStyle: FontStyle.italic, color: tokens.textSecondary),
              ),
            ],
          ),
        ),

        const SizedBox(height: FrameSpace.x6),

        // Paired devices
        FrameSection(
          title: strings.remoteAuthorizedDevicesTitle(_devices.length),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_devices.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    icon: Icon(Icons.delete_forever_outlined, size: FrameSize.icon, color: tokens.danger),
                    label: Text(strings.remoteRevokeAllBtn, style: text.label.copyWith(color: tokens.danger)),
                    onPressed: _revokeAllDevices,
                  ),
                ),
              if (_devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: FrameSpace.x3),
                  child: Text(
                    strings.remoteNoDevicesAuthorized,
                    style: text.body.copyWith(color: tokens.textSecondary),
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
                    margin: const EdgeInsets.only(top: FrameSpace.x2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FrameSpace.x3,
                      vertical: FrameSpace.x2 + FrameSpace.x1 / 2,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          name.contains('iOS') || name.contains('Android')
                              ? Icons.smartphone_outlined
                              : Icons.devices_outlined,
                          color: tokens.accent,
                          size: FrameSize.iconLg,
                        ),
                        const SizedBox(width: FrameSpace.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.body.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: FrameSpace.x2),
                                  FrameStatusTag(
                                    label: isControl ? 'CONTROL' : 'VIEW',
                                    tone: isControl ? FrameStatusTone.warning : FrameStatusTone.info,
                                  ),
                                ],
                              ),
                              const SizedBox(height: FrameSpace.x1 / 2),
                              Text(
                                strings.remoteDeviceInfoLine(ip, lastStr, expiresStr),
                                style: text.caption.copyWith(color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        DropdownButton<String>(
                          value: mode,
                          underline: const SizedBox(),
                          items: [
                            DropdownMenuItem(
                              value: 'view',
                              child: Text(strings.remoteDeviceModeViewLabel, style: text.label),
                            ),
                            DropdownMenuItem(
                              value: 'control',
                              child: Text(strings.remoteDeviceModeControlLabel, style: text.label),
                            ),
                          ],
                          onChanged: (newMode) {
                            if (newMode != null) {
                              _changeDeviceMode(deviceId, mode, newMode, name);
                            }
                          },
                        ),
                        const SizedBox(width: FrameSpace.x2),
                        PressFeedback(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: tokens.danger,
                              side: BorderSide(color: tokens.danger.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: FrameSpace.x2 + FrameSpace.x1 / 2,
                                vertical: FrameSpace.x1,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _revokeDevice(deviceId, name),
                            child: Text(strings.remoteRevokeBtn, style: text.label),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),

        const SizedBox(height: FrameSpace.x6),

        // Provider configuration
        FrameSection(
          title: strings.remoteProviderConfigTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: FrameSize.rowForm,
                padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(color: tokens.inputBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _tunnelProvider,
                    items: [
                      DropdownMenuItem(value: 'tailscale', child: Text(strings.remoteProviderTailscale)),
                      DropdownMenuItem(value: 'cloudflared', child: Text(strings.remoteProviderCloudflared)),
                      DropdownMenuItem(value: 'custom', child: Text(strings.remoteProviderCustom)),
                    ],
                    onChanged: _enabled ? null : (val) => setState(() => _tunnelProvider = val!),
                  ),
                ),
              ),

              if (_tunnelProvider == 'tailscale') ...[
                const SizedBox(height: FrameSpace.x3),
                if (!_tailscaleInstalled)
                  FrameCallout(
                    keyPrefix: 'remote-tailscale-missing',
                    tone: missingBinaryTone,
                    title: strings.remoteTailscaleNotInstalledTitle,
                    strings: strings,
                    body: Text(strings.remoteTailscaleNotInstalledDesc),
                    action: PressFeedback(
                      enabled: (_isInstallingTailscale ? null : _installTailscale) != null,
                      child: OutlinedButton.icon(
                        icon: _isInstallingTailscale
                            ? FrameActivityIndicator(size: FrameSize.icon, strokeWidth: 2, color: tokens.accent)
                            : const Icon(Icons.download_outlined, size: FrameSize.icon),
                        label: Text(
                          _isInstallingTailscale
                              ? strings.remoteTailscaleInstallingBtn
                              : strings.remoteTailscaleInstallAutoBtn,
                        ),
                        onPressed: _isInstallingTailscale ? null : _installTailscale,
                      ),
                    ),
                  )
                else if (!_tailscaleRunning)
                  FrameCallout(
                    keyPrefix: 'remote-tailscale-stopped',
                    tone: FrameCalloutTone.warning,
                    title: strings.remoteTailscaleNotRunning,
                    strings: strings,
                  )
                else
                  FrameCallout(
                    keyPrefix: 'remote-tailscale-active',
                    tone: FrameCalloutTone.info,
                    title: strings.remoteTailscaleActiveTitle,
                    strings: strings,
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_tailscaleDomain != null) ...[
                          Text(
                            strings.remoteTailscalePermanentAddress(_tailscaleDomain!),
                            style: text.mono.copyWith(color: tokens.textPrimary),
                          ),
                          const SizedBox(height: FrameSpace.x3),
                        ],
                        Text(
                          strings.remoteTailscaleCustomizeHostname,
                          style: text.label.copyWith(color: tokens.textSecondary),
                        ),
                        const SizedBox(height: FrameSpace.x1),
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
                            const SizedBox(width: FrameSpace.x3),
                            PressFeedback(
                              enabled: (_isSavingTailscaleHostname ? null : _saveTailscaleHostname) != null,
                              child: FilledButton(
                                onPressed: _isSavingTailscaleHostname ? null : _saveTailscaleHostname,
                                child: _isSavingTailscaleHostname
                                    ? FrameActivityIndicator(
                                        size: FrameSize.icon,
                                        strokeWidth: 2,
                                        color: tokens.accentContrast,
                                      )
                                    : Text(strings.remoteTailscaleSaveNameBtn),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],

              if (_tunnelProvider == 'cloudflared') ...[
                const SizedBox(height: FrameSpace.x3),
                if (_cloudflaredInstalled)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FrameStatusTag(
                        key: const ValueKey('remote-cloudflared-status'),
                        label: strings.remoteCloudflaredDetectedTitle,
                        tone: FrameStatusTone.success,
                      ),
                      if (_cloudflaredPath != null) ...[
                        const SizedBox(width: FrameSpace.x2),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: FrameSpace.x2 / 2),
                            child: Text(
                              _cloudflaredPath!,
                              overflow: TextOverflow.ellipsis,
                              style: text.mono.copyWith(color: tokens.textMuted),
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  FrameCallout(
                    keyPrefix: 'remote-cloudflared-missing',
                    tone: missingBinaryTone,
                    title: strings.remoteCloudflaredNotFoundTitle,
                    strings: strings,
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(strings.remoteCloudflaredNotFoundDesc),
                        const SizedBox(height: FrameSpace.x1),
                        Text(
                          strings.remoteCloudflaredInstallNote,
                          style: text.caption.copyWith(fontStyle: FontStyle.italic, color: tokens.textSecondary),
                        ),
                      ],
                    ),
                    action: PressFeedback(
                      enabled: (_isInstallingCloudflared ? null : _installCloudflared) != null,
                      child: OutlinedButton.icon(
                        icon: _isInstallingCloudflared
                            ? FrameActivityIndicator(size: FrameSize.icon, strokeWidth: 2, color: tokens.accent)
                            : const Icon(Icons.download_outlined, size: FrameSize.icon),
                        label: Text(
                          _isInstallingCloudflared
                              ? strings.remoteCloudflaredInstallingBtn
                              : strings.remoteCloudflaredInstallAutoBtn,
                        ),
                        onPressed: _isInstallingCloudflared ? null : _installCloudflared,
                      ),
                    ),
                  ),
              ],

              if (_localPort != null) ...[
                const SizedBox(height: FrameSpace.x2 + FrameSpace.x1 / 2),
                Text(
                  strings.remoteDedicatedListenerPort(_localPort!),
                  style: text.mono.copyWith(color: tokens.textMuted),
                ),
              ],

              if (_tunnelProvider == 'custom') ...[
                const SizedBox(height: FrameSpace.x3),
                TextField(
                  controller: _customUrlController,
                  decoration: InputDecoration(
                    labelText: strings.remoteCustomHttpsUrlLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: FrameSpace.x2 + FrameSpace.x1 / 2),
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
      ],
    );
  }

  /// Remote status uses the shared [FrameStatusTag] vocabulary.
  Widget _buildStatusBadge(ColorScheme colorScheme, FrameTokens tokens, AppStrings strings) {
    final (label, tone) = switch (_state) {
      'running' => (strings.remoteStatusActive, FrameStatusTone.success),
      'starting' => (strings.remoteStatusStarting, FrameStatusTone.warning),
      'error' => (strings.remoteStatusError, FrameStatusTone.danger),
      _ => (strings.remoteStatusDisabled, FrameStatusTone.neutral),
    };
    return FrameStatusTag(key: const ValueKey('remote-status-tag'), label: label, tone: tone);
  }
}
