import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_locator.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../data/terminal/terminal_settings.dart';
import '../../data/theme/theme_providers.dart';
import '../../data/notifications/notification_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_settings.dart';
import '../../data/composer/composer_settings.dart';
import '../../data/metrics/nerd_stats_settings.dart';
import '../../data/motion/reduced_motion_settings.dart';
import '../../data/transcript/step_grouping_settings.dart';
import '../../domain/session/transcript_grouping.dart';
import '../../data/update/startup_updates_provider.dart';
import '../../domain/update/semver.dart';
import 'diagnostics.dart';
import 'pi_cli_section.dart';
import 'remote_section.dart';
import 'updates_section.dart';
import 'theme_editor_dialog.dart';
import 'agents_section.dart';
import '../../ui/frame_snack_bar.dart';

/// `dart:io` Platform throws `UnsupportedError` on the web build, so every OS
/// branch in settings goes through this web-safe helper.
bool get _isWindowsOs => !kIsWeb && Platform.isWindows;

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
  double? _packageUpdateProgress;
  String? _packageUpdateError;
  bool _isRestartingDaemon = false;
  String? _packageError;
  List<Map<String, dynamic>> _packages = [];
  int _packageListRequest = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 10,
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
      final res = await client.getDaemonConfig().timeout(
        const Duration(seconds: 4),
      );
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

  Future<void> _restartDaemon() async {
    setState(() => _isRestartingDaemon = true);
    try {
      final endpoint = await DaemonLocator.restartDaemon();
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        if (endpoint != null) {
          ref.invalidate(daemonEndpointProvider);
          _fetchDaemonConfig();
          _fetchPiPackages();
          FrameSnackBar.show(
            context,
            message: strings.daemonRestartSuccess,
          );
        } else {
          FrameSnackBar.show(
            context,
            message: strings.daemonRestartFailed,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(
          context,
          message: strings.daemonRestartError(e),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestartingDaemon = false);
    }
  }

  Future<void> _fetchPiPackages() async {
    final request = ++_packageListRequest;
    final client = ref.read(pcpClientProvider);
    final strings = ref.read(appStringsProvider);
    if (client == null) {
      if (mounted) {
        setState(() {
          _packages = [];
          _packageError = strings.daemonNotConnected;
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
      final result = await client.listPiPackages(checkUpdates: true);
      final data = result['data'] as Map<String, dynamic>? ?? result;
      final rawPackages = data['packages'];
      if (rawPackages is! List) {
        throw const FormatException('Invalid Pi package list.');
      }
      final packages = rawPackages.cast<Map<String, dynamic>>().toList();
      if (mounted && request == _packageListRequest) {
        setState(() => _packages = packages);
      }
    } catch (error) {
      if (mounted && request == _packageListRequest) {
        setState(() => _packageError = error.toString());
      }
    } finally {
      if (mounted && request == _packageListRequest) {
        setState(() => _isLoadingPackages = false);
      }
    }
  }

  Future<bool> _confirmPackageAction(
    String title,
    String message,
    String confirmation, {
    bool destructive = false,
  }) async {
    final strings = ref.read(appStringsProvider);
    return await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            autofocus: destructive,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: dialogContext.tokens.danger,
                    foregroundColor: dialogContext.tokens.surface,
                  )
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmation),
          ),
        ],
      ),
    ) ??
    false;
  }

  Future<void> _performPackageAction(
    String source,
    Future<Map<String, dynamic>> Function(PcpClient client) action, {
    required String successMessage,
    String Function(Map<String, dynamic> result)? resultMessage,
  }) async {
    if (!mounted) return;
    final client = ref.read(pcpClientProvider);
    if (client == null || _isWorkingWithPackage) return;
    final updates = ref.read(startupUpdatesProvider.notifier);
    final strings = ref.read(appStringsProvider);
    setState(() {
      _isWorkingWithPackage = true;
      _packageUpdateError = null;
    });
    try {
      final result = await action(client);
      final data = result['data'] as Map<String, dynamic>? ?? result;
      if (mounted) {
        final message = resultMessage?.call(data) ??
            strings.packageActionNotice(successMessage, source);
        final needsRestart =
            data['status'] != 'current' && data['status'] != 'pinned';
        FrameSnackBar.show(
          context,
          message:
              '$message${needsRestart ? ' ${strings.restartPiAfterPackageUpdate}' : ''}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _packageUpdateError = '$source: $error');
        FrameSnackBar.show(
          context,
          message: strings.packageActionFailedNotice(error),
        );
      }
    } finally {
      await updates.refreshPackages();
      if (mounted) {
        await _fetchPiPackages();
        if (mounted) {
          final checkError = ref.read(startupUpdatesProvider).error;
          setState(() {
            _isWorkingWithPackage = false;
            if (checkError != null) {
              _packageUpdateError = [
                ?_packageUpdateError,
                strings.packageUpdateCheckFailed(checkError),
              ].join('\n');
            }
          });
        }
      }
    }
  }

  Future<Map<String, dynamic>> _updateVerifiedPackage(
    PcpClient client,
    String source,
    AppStrings strings,
  ) async {
    final result = await client.updatePiPackage(source);
    final data = result['data'] as Map<String, dynamic>? ?? result;
    if (!const {'updated', 'current', 'pinned'}.contains(data['status'])) {
      throw StateError(strings.packageUpdateNotVerified);
    }
    if (source.startsWith('npm:') &&
        data['status'] != 'pinned' &&
        SemVer.tryParse(data['version']?.toString()) == null) {
      throw StateError(strings.packageUpdateNotVerified);
    }
    return data;
  }

  Future<void> _updatePackage(Map<String, dynamic> package) async {
    final strings = ref.read(appStringsProvider);
    if (_isWorkingWithPackage ||
        _isLoadingPackages ||
        !hasAvailablePiPackageUpdate(package)) {
      return;
    }
    final source = package['source'].toString();
    if (!await _confirmPackageAction(
      strings.confirmPackageUpdateTitle,
      strings.confirmPackageUpdateDesc(source),
      strings.actionUpdate,
    )) {
      return;
    }
    final currentPackage = _packages
        .where((item) => item['source'] == source)
        .firstOrNull;
    if (!mounted ||
        _isWorkingWithPackage ||
        _isLoadingPackages ||
        currentPackage == null ||
        !hasAvailablePiPackageUpdate(currentPackage)) {
      return;
    }
    await _performPackageAction(
      source,
      (client) =>
          _updateVerifiedPackage(client, source, ref.read(appStringsProvider)),
      successMessage: strings.packageUpdatedSuccess,
      resultMessage: (result) {
        final strings = ref.read(appStringsProvider);
        final version = result['version']?.toString();
        switch (result['status']) {
          case 'current':
            return strings.packageAlreadyCurrent(source, version);
          case 'pinned':
            return strings.packageVersionPinned(source, version);
          default:
            return strings.packageVersionUpdated(
              source,
              result['previousVersion']?.toString(),
              version,
            );
        }
      },
    );
  }

  Future<void> _updateAllPackages() async {
    if (_isWorkingWithPackage || _isLoadingPackages) {
      return;
    }
    final strings = ref.read(appStringsProvider);
    final sources = _packages
        .where(hasAvailablePiPackageUpdate)
        .map((package) => (package['source'] ?? '').toString())
        .toSet()
        .toList();
    if (sources.isEmpty) return;
    if (!await _confirmPackageAction(
          strings.updateAllPackagesTitle,
          strings.updateAllPackagesMessage(sources.length),
          strings.updateAllPackages,
        ) ||
        !mounted) {
      return;
    }
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      FrameSnackBar.show(context, message: strings.packagesDaemonDisconnected);
      return;
    }
    if (_isWorkingWithPackage || _isLoadingPackages) return;
    final availableSources = _packages
        .where(hasAvailablePiPackageUpdate)
        .map((package) => package['source'].toString())
        .toSet();
    sources.retainWhere(availableSources.contains);
    if (sources.isEmpty) return;
    final updates = ref.read(startupUpdatesProvider.notifier);
    setState(() {
      _isWorkingWithPackage = true;
      _packageUpdateProgress = 0;
      _packageUpdateError = null;
    });
    final failures = <String>[];
    var updated = 0;
    var current = 0;
    var pinned = 0;
    try {
      for (var index = 0; index < sources.length; index++) {
        final source = sources[index];
        try {
          final result = await _updateVerifiedPackage(client, source, strings);
          switch (result['status']) {
            case 'current':
              current++;
            case 'pinned':
              pinned++;
            default:
              updated++;
          }
        } catch (error) {
          failures.add('$source: $error');
        }
        if (mounted) {
          setState(() => _packageUpdateProgress = (index + 1) / sources.length);
        }
      }
      await updates.refreshPackages();
      if (!mounted) return;
      await _fetchPiPackages();
      if (!mounted) return;
      final result = current == 0 && pinned == 0
          ? failures.isEmpty
                ? strings.packagesUpdated(updated)
                : strings.packageUpdatesFailed(updated, failures.length)
          : '${strings.packageUpdateSummary(updated, current, pinned)}'
                '${failures.isEmpty ? '' : ' ${strings.packageUpdateFailures(failures.length)}'}';
      final checkError = ref.read(startupUpdatesProvider).error;
      final details = [
        ...failures,
        if (checkError != null) strings.packageUpdateCheckFailed(checkError),
      ];
      if (details.isNotEmpty) {
        setState(() => _packageUpdateError = '$result\n${details.join('\n')}');
      }
      FrameSnackBar.show(
        context,
        message:
            '$result${updated == 0 ? '' : ' ${strings.restartPiAfterPackageUpdate}'}',
        duration: Duration(seconds: details.isEmpty ? 3 : 8),
        backgroundColor: details.isEmpty ? null : context.tokens.danger,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isWorkingWithPackage = false;
          _packageUpdateProgress = null;
        });
      }
    }
  }

  Future<void> _removePackage(Map<String, dynamic> package) async {
    final strings = ref.read(appStringsProvider);
    final source = package['source'].toString();
    if (!await _confirmPackageAction(
      strings.confirmPackageRemoveTitle,
      strings.confirmPackageRemoveDesc(source),
      strings.actionRemove,
      destructive: true,
    )) {
      return;
    }
    await _performPackageAction(
      source,
      (client) => client.removePiPackage(source),
      successMessage: strings.packageRemovedSuccess,
    );
  }

  Future<void> _pinPackage(Map<String, dynamic> package) async {
    final strings = ref.read(appStringsProvider);
    final source = package['source'].toString();
    final currentVersion =
        (package['pinnedVersion'] ?? package['version'] ?? '').toString();
    var version = currentVersion;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(strings.pinNpmVersionTitle),
          content: TextFormField(
            initialValue: currentVersion,
            onChanged: (value) => setDialogState(() => version = value.trim()),
            decoration: InputDecoration(
              labelText: strings.semverVersionLabel,
              hintText: '1.2.3',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: version.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, version),
              child: Text(strings.actionPin),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (!await _confirmPackageAction(
      strings.confirmPinTitle,
      strings.confirmPinDesc(source, selected),
      strings.actionPinVersion,
    )) {
      return;
    }
    await _performPackageAction(
      source,
      (client) => client.pinPiPackage(source, selected),
      successMessage: strings.versionPinnedSuccess,
    );
  }

  Widget _packageList(FrameTokens tokens, AppStrings strings) {
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
              label: Text(strings.retryAction),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Text(
              strings.packagesInstalledTitle,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            );
            final button = FilledButton.icon(
              key: const ValueKey('update-all-pi-packages'),
              onPressed:
                  _isWorkingWithPackage ||
                      !_packages.any(hasAvailablePiPackageUpdate)
                  ? null
                  : _updateAllPackages,
              icon: const Icon(Icons.system_update_alt, size: 18),
              label: Text(
                _packageUpdateProgress == null
                    ? strings.updateAllPackages
                    : strings.updatingPackages,
              ),
            );
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 12), button],
              );
            }
            return Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                button,
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          strings.packagesInstalledSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
        if (_isWorkingWithPackage) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            color: tokens.accent,
            value: _packageUpdateProgress,
          ),
        ],
        if (_packageUpdateError != null) ...[
          const SizedBox(height: 12),
          Text(
            _packageUpdateError!,
            key: const ValueKey('pi-package-update-error'),
            style: TextStyle(color: tokens.danger, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        if (_packages.isEmpty)
          Text(
            strings.noPackagesInstalled,
            style: TextStyle(color: tokens.textMuted),
          ),
        for (final package in _packages) _buildPackageCard(tokens, package, strings),
      ],
    );
  }

  Widget _buildPackageCard(FrameTokens tokens, Map<String, dynamic> package, AppStrings strings) {
    final source = package['source']?.toString() ?? '';
    final name = package['name']?.toString() ?? source;
    final version = package['version']?.toString() ?? strings.unknownVersion;
    final pin = package['pinnedVersion']?.toString();
    final updateError = package['updateError']?.toString();
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
                  if (updateError != null)
                    Text(
                      ref
                          .watch(appStringsProvider)
                          .packageUpdateUnavailable(
                            package['latestVersion']?.toString() ?? '?',
                            updateError,
                          ),
                      style: TextStyle(color: tokens.danger, fontSize: 11),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: strings.updatePackageTooltip(name),
              onPressed:
                  _isWorkingWithPackage || !hasAvailablePiPackageUpdate(package)
                  ? null
                  : () => _updatePackage(package),
              icon: const Icon(Icons.system_update_alt, size: 18),
            ),
            if (supportsPin)
              IconButton(
                tooltip: strings.pinPackageTooltip(name),
                onPressed: _isWorkingWithPackage
                    ? null
                    : () => _pinPackage(package),
                icon: const Icon(Icons.push_pin_outlined, size: 18),
              ),
            IconButton(
              tooltip: strings.removePackageTooltip(name),
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
    final strings = ref.read(appStringsProvider);

    setState(() {
      _workerIdleTimeoutMinutes = newMinutes;
      _configStatusMessage = strings.timeoutSavingStatus;
    });

    try {
      await client.setDaemonConfig({'workerIdleTimeoutMs': newMinutes * 60000});
      if (mounted) {
        setState(() {
          _configStatusMessage = strings.timeoutUpdatedStatus;
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
          _configStatusMessage = strings.timeoutErrorStatus(e);
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
    ref.listen<StartupUpdateState>(startupUpdatesProvider, (previous, next) {
      if (previous?.isChecking == true &&
          !next.isChecking &&
          !_isWorkingWithPackage) {
        _fetchPiPackages();
      }
    });
    ref.listen<AsyncValue<DaemonConnectionState>>(connectionStateProvider, (
      prev,
      next,
    ) {
      if (next.value == DaemonConnectionState.connected) {
        _fetchDaemonConfig();
        _fetchPiPackages();
      }
    });

    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final endpointAsync = ref.watch(daemonEndpointProvider);
    final endpoint = endpointAsync.value;

    final settingsContent = Container(
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
                      key: const ValueKey('settings-back-button'),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: strings.backToWorkspaceTooltip,
                      color: tokens.displayText,
                      onPressed: widget.onClose,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.settingsTitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.displayText,
                          fontSize: 28,
                          height: 1,
                          fontFamily: tokens.headingFontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: tokens.accent,
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
                  tabs: [
                    Tab(text: strings.tabPiCli),
                    Tab(text: strings.tabPackages),
                    Tab(text: strings.tabDaemon),
                    Tab(text: strings.tabAppearance),
                    Tab(text: strings.tabPrivacy),
                    Tab(text: strings.tabDiagnostics),
                    Tab(text: strings.tabUpdates),
                    Tab(text: strings.tabTerminal),
                    Tab(text: strings.tabRemote),
                    Tab(text: strings.tabAgents),
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
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    // -------------------------------------------------------------
                    // Tab 1: Pi CLI
                    // -------------------------------------------------------------
                    PiCliSection(
                      tokens: tokens,
                      strings: strings,
                      onRecheck: () {
                        ref.invalidate(daemonEndpointProvider);
                      },
                      onPackagesChanged: () async {
                        await ref
                            .read(startupUpdatesProvider.notifier)
                            .refreshPackages();
                        if (!mounted) return;
                        await _fetchPiPackages();
                        if (!mounted) return;
                        final error = ref.read(startupUpdatesProvider).error;
                        if (error != null) {
                          setState(
                            () => _packageUpdateError = strings
                                .packageUpdateCheckFailed(error),
                          );
                        }
                      },
                    ),

                    // -------------------------------------------------------------
                    // Tab 2: Pacchetti Pi
                    // -------------------------------------------------------------
                    _packageList(tokens, strings),

                    // -------------------------------------------------------------
                    // Tab 3: Daemon
                    // -------------------------------------------------------------
                    ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          strings.daemonStatusTitle,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.daemonStatusSubtitle,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoCard(tokens, [
                          _buildInfoRow(
                            tokens,
                            strings.labelHttpWsPort,
                            endpoint != null
                                ? '127.0.0.1:${endpoint.port}'
                                : strings.labelConnecting,
                          ),
                          _buildInfoRow(
                            tokens,
                            strings.labelStatus,
                            endpoint == null
                                ? strings.labelNotConnected
                                : strings.labelEndpointDetected,
                          ),
                          _buildInfoRow(
                            tokens,
                            strings.labelProtocol,
                            strings.protocolPcp1,
                          ),
                        ]),
                        const SizedBox(height: 24),
                        Text(
                          strings.workerIdleTimeoutTitle,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          strings.workerIdleTimeoutSubtitle,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _isLoadingConfig
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
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
                                        items: [
                                          DropdownMenuItem(
                                            value: 0,
                                            child: Text(strings.timeoutNever),
                                          ),
                                          DropdownMenuItem(
                                            value: 5,
                                            child: Text(strings.timeout5Min),
                                          ),
                                          DropdownMenuItem(
                                            value: 15,
                                            child: Text(strings.timeout15Min),
                                          ),
                                          DropdownMenuItem(
                                            value: 30,
                                            child: Text(strings.timeout30Min),
                                          ),
                                          DropdownMenuItem(
                                            value: 60,
                                            child: Text(strings.timeout1Hour),
                                          ),
                                          DropdownMenuItem(
                                            value: 120,
                                            child: Text(strings.timeout2Hours),
                                          ),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) {
                                            _updateTimeout(val);
                                          }
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
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tokens.surfaceElevated,
                              foregroundColor: tokens.textPrimary,
                            ),
                            icon: _isRestartingDaemon
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tokens.accent,
                                    ),
                                  )
                                : const Icon(Icons.restart_alt, size: 16),
                            label: Text(
                              _isRestartingDaemon
                                  ? strings.restartingDaemonStatus
                                  : strings.restartDaemonBtn,
                            ),
                            onPressed: _isRestartingDaemon
                                ? null
                                : _restartDaemon,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          strings.notificationsSectionTitle,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          strings.notificationsSectionSubtitle,
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
                              strings.notificationsSwitchTitle,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                            value: ref.watch(notificationsEnabledProvider),
                            activeThumbColor: tokens.accent,
                            onChanged: (val) {
                              ref
                                      .read(
                                        notificationsEnabledProvider.notifier,
                                      )
                                      .state =
                                  val;
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
                        final settings = ref.watch(themeSettingsProvider);
                        final repo = ref.watch(themeRepositoryProvider);
                        final themes = repo.availableThemes;
                        final darkThemes = themes
                            .where((t) => t.variant == 'dark')
                            .toList();
                        final lightThemes = themes
                            .where((t) => t.variant == 'light')
                            .toList();

                        return ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            Text(
                              strings.languageSectionTitle,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              strings.languageSectionSubtitle,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusMd,
                                ),
                                border: Border.all(color: tokens.border),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<AppLanguage>(
                                  key: const ValueKey(
                                    'settings-language-dropdown',
                                  ),
                                  isExpanded: true,
                                  value: ref.watch(appLanguageProvider),
                                  dropdownColor: tokens.surfaceElevated,
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 13,
                                    fontFamily: tokens.uiFontFamily,
                                  ),
                                  items: AppLanguage.values.map((lang) {
                                    return DropdownMenuItem<AppLanguage>(
                                      value: lang,
                                      child: Row(
                                        children: [
                                          Text(
                                            lang.flag,
                                            style: const TextStyle(
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(lang.label),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (newLang) {
                                    if (newLang != null) {
                                      ref
                                          .read(appLanguageProvider.notifier)
                                          .setLanguage(newLang);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              strings.appearanceTitle,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              strings.appearanceSubtitle,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: tokens.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusMd,
                                ),
                                border: Border.all(color: tokens.border),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          strings.useSystemTheme,
                                          style: TextStyle(
                                            color: tokens.textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          strings.useSystemThemeSubtitle,
                                          style: TextStyle(
                                            color: tokens.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    key: const ValueKey(
                                      'settings-theme-system-switch',
                                    ),
                                    value: settings.useSystemTheme,
                                    onChanged: (val) {
                                      ref
                                          .read(themeSettingsProvider.notifier)
                                          .setUseSystemTheme(val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (!settings.useSystemTheme) ...[
                              Text(
                                strings.selectActiveTheme,
                                style: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
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
                                    key: const ValueKey(
                                      'settings-theme-dropdown',
                                    ),
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
                                              activeThemeSpecProvider.notifier,
                                            )
                                            .setTheme(newId);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        strings.defaultDarkTheme,
                                        style: TextStyle(
                                          color: tokens.textSecondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tokens.surfaceElevated,
                                          borderRadius: BorderRadius.circular(
                                            tokens.radiusMd,
                                          ),
                                          border: Border.all(
                                            color: tokens.border,
                                          ),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            isExpanded: true,
                                            borderRadius: BorderRadius.circular(
                                              tokens.radiusMd,
                                            ),
                                            value:
                                                darkThemes.any(
                                                  (t) =>
                                                      t.id ==
                                                      settings
                                                          .defaultDarkThemeId,
                                                )
                                                ? settings.defaultDarkThemeId
                                                : (darkThemes.isNotEmpty
                                                      ? darkThemes.first.id
                                                      : null),
                                            dropdownColor:
                                                tokens.surfaceElevated,
                                            style: TextStyle(
                                              color: tokens.textPrimary,
                                              fontSize: 13,
                                              fontFamily: tokens.uiFontFamily,
                                            ),
                                            items: darkThemes.map((t) {
                                              return DropdownMenuItem<String>(
                                                value: t.id,
                                                child: Text(
                                                  t.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (newId) {
                                              if (newId != null) {
                                                ref
                                                    .read(
                                                      themeSettingsProvider
                                                          .notifier,
                                                    )
                                                    .setDefaultDarkTheme(newId);
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        strings.defaultLightTheme,
                                        style: TextStyle(
                                          color: tokens.textSecondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tokens.surfaceElevated,
                                          borderRadius: BorderRadius.circular(
                                            tokens.radiusMd,
                                          ),
                                          border: Border.all(
                                            color: tokens.border,
                                          ),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            isExpanded: true,
                                            borderRadius: BorderRadius.circular(
                                              tokens.radiusMd,
                                            ),
                                            value:
                                                lightThemes.any(
                                                  (t) =>
                                                      t.id ==
                                                      settings
                                                          .defaultLightThemeId,
                                                )
                                                ? settings.defaultLightThemeId
                                                : (lightThemes.isNotEmpty
                                                      ? lightThemes.first.id
                                                      : null),
                                            dropdownColor:
                                                tokens.surfaceElevated,
                                            style: TextStyle(
                                              color: tokens.textPrimary,
                                              fontSize: 13,
                                              fontFamily: tokens.uiFontFamily,
                                            ),
                                            items: lightThemes.map((t) {
                                              return DropdownMenuItem<String>(
                                                value: t.id,
                                                child: Text(
                                                  t.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (newId) {
                                              if (newId != null) {
                                                ref
                                                    .read(
                                                      themeSettingsProvider
                                                          .notifier,
                                                    )
                                                    .setDefaultLightTheme(
                                                      newId,
                                                    );
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  key: const ValueKey(
                                    'settings-open-theme-editor-btn',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: tokens.accent),
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
                                    Icons.palette_outlined,
                                    size: 16,
                                    color: tokens.accent,
                                  ),
                                  label: Text(
                                    strings.openThemeEditorBtn,
                                    style: TextStyle(
                                      color: tokens.accent,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onPressed: () {
                                    ThemeEditorDialog.show(context);
                                  },
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey(
                                    'settings-import-theme-btn',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: tokens.borderStrong,
                                    ),
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
                                    strings.importThemeBtn,
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
                                          XTypeGroup(
                                            label: strings.themeJsonFilterLabel,
                                            extensions: const ['json'],
                                          ),
                                        ],
                                      );
                                      if (file == null || !context.mounted) {
                                        return;
                                      }
                                      final content = await file.readAsString();
                                      final importedSpec = await ref
                                          .read(
                                            activeThemeSpecProvider.notifier,
                                          )
                                          .importThemeFromJson(content);
                                      if (context.mounted) {
                                        FrameSnackBar.show(
                                          context,
                                          message: strings.themeImportSuccess(importedSpec.name),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        FrameSnackBar.show(
                                          context,
                                          message: strings.themeImportError(e),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildInfoCard(tokens, [
                              _buildInfoRow(
                                tokens,
                                strings.labelActiveTheme,
                                '${activeTheme.name} (v${activeTheme.version})',
                              ),
                              _buildInfoRow(
                                tokens,
                                strings.labelLayoutDensity,
                                strings.layoutDensityDefault,
                              ),
                              _buildInfoRow(
                                tokens,
                                strings.labelFonts,
                                strings.fontsDetail(
                                  activeTheme.toTokens().uiFontFamily,
                                  activeTheme.toTokens().monoFontFamily,
                                ),
                              ),
                            ]),
                            if (activeTheme.diagnostics.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                strings.themeDiagnosticsHeader,
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
                            const SizedBox(height: 24),
                            Text(
                              strings.composerSectionTitle,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              strings.sendWithEnterSubtitle,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusMd,
                                ),
                                border: Border.all(color: tokens.border),
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: SwitchListTile(
                                  key: const ValueKey(
                                    'settings-composer-send-with-enter-switch',
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    strings.sendWithEnterTitle,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: 13,
                                      fontFamily: tokens.uiFontFamily,
                                    ),
                                  ),
                                  activeThumbColor: tokens.accent,
                                  value: ref
                                      .watch(composerSettingsProvider)
                                      .sendWithEnter,
                                  onChanged: (val) {
                                    ref
                                        .read(
                                          composerSettingsProvider.notifier,
                                        )
                                        .setSendWithEnter(val);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              strings.reducedMotionSectionTitle,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              strings.reducedMotionSubtitle,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusMd,
                                ),
                                border: Border.all(color: tokens.border),
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: SwitchListTile(
                                  key: const ValueKey(
                                    'settings-reduced-motion-switch',
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    strings.reducedMotionTitle,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: 13,
                                      fontFamily: tokens.uiFontFamily,
                                    ),
                                  ),
                                  activeThumbColor: tokens.accent,
                                  value: ref
                                      .watch(reducedMotionSettingsProvider)
                                      .enabled,
                                  onChanged: (val) {
                                    ref
                                        .read(
                                          reducedMotionSettingsProvider.notifier,
                                        )
                                        .setEnabled(val);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              strings.nerdStatsSectionTitle,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              strings.nerdStatsSubtitle,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusMd,
                                ),
                                border: Border.all(color: tokens.border),
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: SwitchListTile(
                                  key: const ValueKey(
                                    'settings-nerd-stats-switch',
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    strings.nerdStatsTitle,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: 13,
                                      fontFamily: tokens.uiFontFamily,
                                    ),
                                  ),
                                  activeThumbColor: tokens.accent,
                                  value: ref
                                      .watch(nerdStatsSettingsProvider)
                                      .enabled,
                                  onChanged: (val) {
                                    ref
                                        .read(
                                          nerdStatsSettingsProvider.notifier,
                                        )
                                        .setEnabled(val);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Builder(
                              builder: (context) {
                                final stepGroupingSettings =
                                    ref.watch(stepGroupingSettingsProvider);
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      strings.stepGroupingSectionTitle,
                                      style: TextStyle(
                                        color: tokens.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      strings.stepGroupingModeDescription(
                                        stepGroupingSettings.mode,
                                      ),
                                      style: TextStyle(
                                        color: tokens.textMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tokens.surfaceElevated,
                                        borderRadius: BorderRadius.circular(
                                          tokens.radiusMd,
                                        ),
                                        border: Border.all(color: tokens.border),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<StepGroupingMode>(
                                          key: const ValueKey(
                                            'settings-step-grouping-mode-dropdown',
                                          ),
                                          isExpanded: true,
                                          value: stepGroupingSettings.mode,
                                          dropdownColor: tokens.surfaceElevated,
                                          style: TextStyle(
                                            color: tokens.textPrimary,
                                            fontSize: 13,
                                            fontFamily: tokens.uiFontFamily,
                                          ),
                                          items: StepGroupingMode.values.map((mode) {
                                            return DropdownMenuItem<StepGroupingMode>(
                                              value: mode,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    strings.stepGroupingModeLabel(
                                                      mode,
                                                    ),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  Text(
                                                    strings
                                                        .stepGroupingModeDescription(
                                                      mode,
                                                    ),
                                                    style: TextStyle(
                                                      color: tokens.textMuted,
                                                      fontSize: 11,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (newMode) {
                                            if (newMode != null) {
                                              ref
                                                  .read(
                                                    stepGroupingSettingsProvider
                                                        .notifier,
                                                  )
                                                  .setMode(newMode);
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tokens.surfaceElevated,
                                        borderRadius: BorderRadius.circular(
                                          tokens.radiusMd,
                                        ),
                                        border: Border.all(color: tokens.border),
                                      ),
                                      child: Material(
                                        type: MaterialType.transparency,
                                        child: SwitchListTile(
                                          key: const ValueKey(
                                            'settings-step-grouping-auto-collapse-switch',
                                          ),
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                            strings.stepGroupingAutoCollapseTitle,
                                            style: TextStyle(
                                              color: tokens.textPrimary,
                                              fontSize: 13,
                                              fontFamily: tokens.uiFontFamily,
                                            ),
                                          ),
                                          subtitle: Text(
                                            strings
                                                .stepGroupingAutoCollapseSubtitle,
                                            style: TextStyle(
                                              color: tokens.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                          activeThumbColor: tokens.accent,
                                          value: stepGroupingSettings.autoCollapse,
                                          onChanged: (val) {
                                            ref
                                                .read(
                                                  stepGroupingSettingsProvider
                                                      .notifier,
                                                )
                                                .setAutoCollapse(val);
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
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
                                strings.privacyTitle,
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
                            strings.privacyCardContent,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          strings.privacyBulletPoints,
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
                    // Tab 8: Terminale & Ambiente di Esecuzione
                    // -------------------------------------------------------------
                    _buildTerminalSettingsTab(tokens, strings),

                    // -------------------------------------------------------------
                    // Tab 9: Accesso Remoto Sicuro
                    // -------------------------------------------------------------
                    const RemoteSection(),

                    // -------------------------------------------------------------
                    // Tab 10: Agenti & Sottoagenti
                    // -------------------------------------------------------------
                    const AgentsSection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(autofocus: true, child: settingsContent),
    );
  }

  Widget _buildTerminalSettingsTab(FrameTokens tokens, AppStrings strings) {
    final termSettings = ref.watch(terminalSettingsProvider);
    final notifier = ref.read(terminalSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          strings.terminalTabTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          strings.terminalTabSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 20),

        // Section 1: Modalità di esecuzione
        Text(
          strings.terminalPreferredModeHeader,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: RadioGroup<TerminalMode>(
            groupValue: termSettings.mode,
            onChanged: (mode) {
              if (mode != null) notifier.setMode(mode);
            },
            child: Column(
              children: [
                RadioListTile<TerminalMode>(
                  value: TerminalMode.integrated,
                  activeColor: tokens.accent,
                  title: Text(
                    strings.terminalIntegratedTitle,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    strings.terminalIntegratedSubtitle,
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                  ),
                ),
                Divider(color: tokens.border, height: 1),
                RadioListTile<TerminalMode>(
                  value: TerminalMode.native,
                  activeColor: tokens.accent,
                  title: Text(
                    strings.terminalNativeTitle,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    strings.terminalNativeSubtitle,
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Section 2: Scelta applicazione terminale nativo
        Text(
          strings.terminalNativeAppHeader,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: RadioGroup<NativeTerminalApp>(
            groupValue: termSettings.nativeApp,
            onChanged: (app) {
              if (app != null) notifier.setNativeApp(app);
            },
            child: Column(
              children: [
                RadioListTile<NativeTerminalApp>(
                  value: NativeTerminalApp.systemDefault,
                  activeColor: tokens.accent,
                  title: Text(
                    strings.terminalNativeAppDefault(_isWindowsOs),
                    style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                  ),
                ),
                if (_isWindowsOs) ...[
                  Divider(color: tokens.border, height: 1),
                  RadioListTile<NativeTerminalApp>(
                    value: NativeTerminalApp.powershell,
                    activeColor: tokens.accent,
                    title: Text(
                      strings.terminalPowershell,
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                    ),
                  ),
                  Divider(color: tokens.border, height: 1),
                  RadioListTile<NativeTerminalApp>(
                    value: NativeTerminalApp.cmd,
                    activeColor: tokens.accent,
                    title: Text(
                      strings.terminalCmd,
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                    ),
                  ),
                  Divider(color: tokens.border, height: 1),
                  RadioListTile<NativeTerminalApp>(
                    value: NativeTerminalApp.wsl,
                    activeColor: tokens.accent,
                    title: Text(
                      strings.terminalWsl,
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                    ),
                  ),
                ],
                Divider(color: tokens.border, height: 1),
                RadioListTile<NativeTerminalApp>(
                  value: NativeTerminalApp.custom,
                  activeColor: tokens.accent,
                  title: Text(
                    strings.terminalCustomApp,
                    style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                  ),
                  subtitle: termSettings.nativeApp == NativeTerminalApp.custom
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller:
                                      TextEditingController(
                                          text: termSettings.customPath,
                                        )
                                        ..selection = TextSelection.collapsed(
                                          offset:
                                              termSettings.customPath.length,
                                        ),
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 12,
                                    fontFamily: tokens.monoFontFamily,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: _isWindowsOs
                                        ? 'C:\\Percorso\\A\\terminal.exe'
                                        : '/usr/bin/alacritty',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (val) =>
                                      notifier.setCustomPath(val.trim()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.folder_open, size: 14),
                                label: Text(strings.terminalBrowseBtn),
                                onPressed: () async {
                                  final file = await openFile(
                                    acceptedTypeGroups: [
                                      XTypeGroup(
                                        label: strings.terminalExecutableFilterLabel,
                                        extensions: const ['exe', 'bat', 'cmd', 'sh'],
                                      ),
                                    ],
                                  );
                                  if (file != null) {
                                    notifier.setCustomPath(file.path);
                                  }
                                },
                              ),
                            ],
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Test action button
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: tokens.surface,
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(strings.terminalTestBtn),
            onPressed: () async {
              final launched = await launchNativeTerminal(
                cwd: Directory.current.path,
                nativeApp: termSettings.nativeApp,
                customPath: termSettings.customPath,
              );
              if (mounted) {
                FrameSnackBar.show(
                  context,
                  message: launched
                      ? strings.terminalTestSuccess
                      : strings.terminalTestFailed,
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(FrameTokens tokens, List<Widget> children) {
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

  Widget _buildInfoRow(FrameTokens tokens, String label, String value) {
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
