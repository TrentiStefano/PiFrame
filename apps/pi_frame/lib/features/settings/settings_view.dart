import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_locator.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_settings.dart';
import '../../domain/errors/user_facing_error.dart';
import '../../data/update/startup_updates_provider.dart';
import '../../domain/update/semver.dart';
import 'diagnostics.dart';
import 'sections/aspetto_section.dart';
import 'sections/daemon_section.dart';
import 'sections/packages_section.dart';
import 'sections/privacy_section.dart';
import 'sections/terminal_section.dart';
import 'pi_cli_section.dart';
import 'remote_section.dart';
import 'updates_section.dart';
import 'agents_section.dart';
import 'package_load_states.dart';
import '../../ui/frame_snack_bar.dart';
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
  Object? _packageError;
  List<Map<String, dynamic>> _packages = [];
  int _packageListRequest = 0;
  Timer? _packageLoadTimer;
  bool _packageLoadSlow = false;

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

  void _cancelPackageLoadTimer() {
    _packageLoadTimer?.cancel();
    _packageLoadTimer = null;
  }

  Future<void> _fetchPiPackages() async {
    final request = ++_packageListRequest;
    final client = ref.read(pcpClientProvider);
    final strings = ref.read(appStringsProvider);
    _cancelPackageLoadTimer();
    if (client == null) {
      if (mounted) {
        setState(() {
          _packages = [];
          _packageError = strings.daemonNotConnected;
          _packageLoadSlow = false;
          _isLoadingPackages = false;
        });
      }
      return;
    }
    setState(() {
      _isLoadingPackages = true;
      _packageLoadSlow = false;
      _packageError = null;
    });
    _packageLoadTimer = Timer(packageLoadSlowThreshold, () {
      if (!mounted || request != _packageListRequest || !_isLoadingPackages) {
        return;
      }
      setState(() => _packageLoadSlow = true);
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
        setState(() => _packageError = error);
      }
    } finally {
      if (request == _packageListRequest) {
        _cancelPackageLoadTimer();
        if (mounted) {
          setState(() {
            _packageLoadSlow = false;
            _isLoadingPackages = false;
          });
        }
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
        setState(
          () => _packageUpdateError =
              '$source: ${describeError(error, strings).summary}',
        );
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
      throw UserMessageException(strings.packageUpdateNotVerified);
    }
    if (source.startsWith('npm:') &&
        data['status'] != 'pinned' &&
        SemVer.tryParse(data['version']?.toString()) == null) {
      throw UserMessageException(strings.packageUpdateNotVerified);
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
          failures.add('$source: ${describeError(error, strings).summary}');
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
    _cancelPackageLoadTimer();
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
                    PackagesSection(
                      tokens: tokens,
                      strings: strings,
                      isLoading: _isLoadingPackages,
                      slow: _packageLoadSlow,
                      loadError: _packageError,
                      packages: _packages,
                      isWorking: _isWorkingWithPackage,
                      updateProgress: _packageUpdateProgress,
                      updateErrorMessage: _packageUpdateError,
                      onRetry: _fetchPiPackages,
                      onUpdateAll: _updateAllPackages,
                      onUpdatePackage: _updatePackage,
                      onPinPackage: _pinPackage,
                      onRemovePackage: _removePackage,
                    ),

                    // -------------------------------------------------------------
                    // Tab 3: Daemon
                    // -------------------------------------------------------------
                    DaemonSection(
                      tokens: tokens,
                      strings: strings,
                      endpoint: endpoint,
                      isLoadingConfig: _isLoadingConfig,
                      workerIdleTimeoutMinutes: _workerIdleTimeoutMinutes,
                      configStatusMessage: _configStatusMessage,
                      isRestartingDaemon: _isRestartingDaemon,
                      onRestartDaemon: _restartDaemon,
                      onUpdateTimeout: _updateTimeout,
                    ),

                    // -------------------------------------------------------------
                    // Tab 4: Aspetto
                    // -------------------------------------------------------------
                    AppearanceSection(tokens: tokens, strings: strings),

                    // -------------------------------------------------------------
                    // Tab 5: Privacy (D16 — Zero Telemetry)
                    // -------------------------------------------------------------
                    PrivacySection(tokens: tokens, strings: strings),

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
                    TerminalSection(tokens: tokens, strings: strings),

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

}
