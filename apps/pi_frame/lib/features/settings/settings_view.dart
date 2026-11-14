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
import '../../data/language/strings_shell.dart';
import '../../domain/errors/user_facing_error.dart';
import '../../data/update/startup_updates_provider.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/update/semver.dart';
import '../../ui/frame_status_tag.dart';
import '../../ui/motion.dart';
import 'diagnostics.dart';
import 'sections/aspetto_section.dart';
import 'sections/daemon_section.dart';
import 'sections/packages_section.dart';
import 'sections/terminal_section.dart';
import 'pi_cli_section.dart';
import 'remote_section.dart';
import 'updates_section.dart';
import 'agents_section.dart';
import 'package_load_states.dart';
import '../../ui/frame_snack_bar.dart';

/// Stable id for [SettingsView.initialSection] that opens Diagnostica (the
/// title-bar connection dot uses it). Callers name a section by id, so the
/// index order of [_SettingsSection] can change without breaking them.
const kSettingsSectionDiagnostics = 'diagnostics';

class SettingsView extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final int initialTabIndex;

  /// Opens on this section id instead of [initialTabIndex] when it is known.
  final String? initialSection;

  const SettingsView({
    super.key,
    required this.onClose,
    this.initialTabIndex = 0,
    this.initialSection,
  });

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  /// From this width the navigation is a left column; below it, a tab row.
  static const double _wideNavBreakpoint = 900;

  /// Width of the left navigation column.
  static const double _navWidth = 220;

  /// Maximum width of the section content column.
  static const double _contentMaxWidth = 760;

  /// Pi CLI is wide enough to hold the console in a right column.
  static const double _wideContentMaxWidth = 1160;

  late _SettingsSection _section;
  // True when the last section change came from the keyboard or a
  // reduced-motion setting: the content then switches without a cross-fade.
  bool _instantSwitch = false;
  final Map<_SettingsSection, FocusNode> _navFocus = {
    for (final section in _SettingsSection.values)
      section: FocusNode(debugLabel: 'settings-nav-${section.name}'),
  };
  final Map<_SettingsSection, GlobalKey> _navItemKeys = {
    for (final section in _SettingsSection.values) section: GlobalKey(),
  };
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
    _section = widget.initialSection == kSettingsSectionDiagnostics
        ? _SettingsSection.diagnostics
        : _SettingsSection.fromIndex(widget.initialTabIndex);
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
          FrameSnackBar.show(context, message: strings.daemonRestartSuccess);
        } else {
          FrameSnackBar.show(context, message: strings.daemonRestartFailed);
        }
      }
    } catch (e) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(context, message: strings.daemonRestartError(e));
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
        final message =
            resultMessage?.call(data) ??
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
    for (final node in _navFocus.values) {
      node.dispose();
    }
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
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);
    final endpoint = ref.watch(daemonEndpointProvider).value;
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final runStatus = activeSessionId == null
        ? null
        : ref.watch(
            sessionStateFamily(activeSessionId)
                .select((state) => state.agentStatus),
          );
    final reduced = FrameMotion.reduced(context);

    Widget sectionBody(_SettingsSection section) {
      return switch (section) {
        _SettingsSection.piCli => PiCliSection(
          tokens: tokens,
          strings: strings,
          onRecheck: () {
            ref.invalidate(daemonEndpointProvider);
          },
          onPackagesChanged: () async {
            await ref.read(startupUpdatesProvider.notifier).refreshPackages();
            if (!mounted) return;
            await _fetchPiPackages();
            if (!mounted) return;
            final error = ref.read(startupUpdatesProvider).error;
            if (error != null) {
              setState(
                () => _packageUpdateError = strings.packageUpdateCheckFailed(
                  error,
                ),
              );
            }
          },
        ),
        _SettingsSection.packages => PackagesSection(
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
        _SettingsSection.daemon => DaemonSection(
          tokens: tokens,
          strings: strings,
          endpoint: endpoint,
          isLoadingConfig: _isLoadingConfig,
          workerIdleTimeoutMinutes: _workerIdleTimeoutMinutes,
          configStatusMessage: _configStatusMessage,
          isRestartingDaemon: _isRestartingDaemon,
          onRestartDaemon: _restartDaemon,
          onUpdateTimeout: _updateTimeout,
          runActive: _isRunActive(runStatus),
        ),
        _SettingsSection.appearance => AppearanceSection(
          tokens: tokens,
          strings: strings,
        ),
        _SettingsSection.diagnostics => const DiagnosticsSection(),
        _SettingsSection.updates => const UpdatesSection(),
        _SettingsSection.terminal => TerminalSection(
          tokens: tokens,
          strings: strings,
        ),
        _SettingsSection.remote => const RemoteSection(),
        _SettingsSection.agents => AgentsSection(
          onOpenPackages: () =>
              setState(() => _section = _SettingsSection.packages),
        ),
      };
    }

    final content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _section == _SettingsSection.piCli
              ? _wideContentMaxWidth
              : _contentMaxWidth,
        ),
        child: AnimatedSwitcher(
          duration: _instantSwitch || reduced
              ? FrameMotion.instant
              : FrameMotion.crossFade,
          child: KeyedSubtree(
            key: ValueKey('settings-section-${_section.name}'),
            child: sectionBody(_section),
          ),
        ),
      ),
    );

    final settingsContent = Container(
      color: tokens.background,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(
              FrameSpace.x2,
              FrameSpace.x2,
              FrameSpace.x2,
              FrameSpace.x1,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: FrameSpace.x4,
              vertical: FrameSpace.x2,
            ),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('settings-back-button'),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: strings.backToWorkspaceTooltip,
                  color: tokens.displayText,
                  onPressed: widget.onClose,
                ),
                const SizedBox(width: FrameSpace.x2),
                Expanded(
                  child: Text(
                    strings.settingsTitle,
                    overflow: TextOverflow.ellipsis,
                    style: text.display.copyWith(
                      color: tokens.displayText,
                      fontFamily: tokens.headingFontFamily,
                    ),
                  ),
                ),
                if (runStatus != null) ...[
                  const SizedBox(width: FrameSpace.x2),
                  Flexible(
                    child: Tooltip(
                      message: strings.settingsRunStatusTooltip,
                      child: FrameStatusTag(
                        key: const ValueKey('settings-run-status'),
                        label: strings.agentStatusLabel(runStatus),
                        tone: _runStatusTone(runStatus),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= _wideNavBreakpoint) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: _navWidth,
                        child: _buildVerticalNav(strings, tokens, text),
                      ),
                      Expanded(child: content),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHorizontalNav(strings, tokens, text),
                    Expanded(child: content),
                  ],
                );
              },
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

  /// Settings sections grouped for the navigation, in display order.
  List<(String, List<_SettingsSection>)> _navGroups(AppStrings strings) => [
    (
      strings.settingsNavGeneral,
      const [
        _SettingsSection.appearance,
        _SettingsSection.terminal,
        _SettingsSection.updates,
      ],
    ),
    (
      strings.settingsNavPi,
      const [
        _SettingsSection.piCli,
        _SettingsSection.packages,
        _SettingsSection.agents,
      ],
    ),
    (
      strings.settingsNavSystem,
      const [
        _SettingsSection.daemon,
        _SettingsSection.diagnostics,
        _SettingsSection.remote,
      ],
    ),
  ];

  String _sectionLabel(_SettingsSection section, AppStrings strings) =>
      switch (section) {
        _SettingsSection.piCli => strings.tabPiCli,
        _SettingsSection.packages => strings.tabPackages,
        _SettingsSection.daemon => strings.tabDaemon,
        _SettingsSection.appearance => strings.tabAppearance,
        _SettingsSection.diagnostics => strings.tabDiagnostics,
        _SettingsSection.updates => strings.tabUpdates,
        _SettingsSection.terminal => strings.tabTerminal,
        _SettingsSection.remote => strings.tabRemote,
        _SettingsSection.agents => strings.tabAgents,
      };

  Widget _buildVerticalNav(
    AppStrings strings,
    FrameTokens tokens,
    FrameText text,
  ) {
    return Focus(
      onKeyEvent: _handleNavKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FrameSpace.x2,
          FrameSpace.x2,
          FrameSpace.x2,
          FrameSpace.x4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (label, sections) in _navGroups(strings)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FrameSpace.x2,
                  FrameSpace.x3,
                  FrameSpace.x2,
                  FrameSpace.x1,
                ),
                child: Text(
                  label,
                  style: text.caption.copyWith(color: tokens.textMuted),
                ),
              ),
              for (final section in sections)
                _SettingsNavItem(
                  label: _sectionLabel(section, strings),
                  name: section.name,
                  selected: section == _section,
                  vertical: true,
                  focusNode: _navFocus[section]!,
                  itemKey: _navItemKeys[section]!,
                  onTap: () => _selectFromPointerOrKeyboard(section),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Narrow layout: one horizontal row of section tabs that scrolls, with
  /// fade edges that show there is more to reach.
  Widget _buildHorizontalNav(
    AppStrings strings,
    FrameTokens tokens,
    FrameText text,
  ) {
    final fadeColor = tokens.surfaceElevated;
    final transparent = fadeColor.withValues(alpha: 0);
    final sections = [for (final group in _navGroups(strings)) ...group.$2];
    return Focus(
      onKeyEvent: _handleNavKey,
      child: Stack(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: FrameSpace.x4,
              vertical: FrameSpace.x2,
            ),
            child: Row(
              children: [
                for (final section in sections)
                  Padding(
                    padding: const EdgeInsets.only(right: FrameSpace.x1),
                    child: _SettingsNavItem(
                      label: _sectionLabel(section, strings),
                      name: section.name,
                      selected: section == _section,
                      vertical: false,
                      focusNode: _navFocus[section]!,
                      itemKey: _navItemKeys[section]!,
                      onTap: () => _selectFromPointerOrKeyboard(section),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: FrameSpace.x4,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [fadeColor, transparent]),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: FrameSpace.x6,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [fadeColor, transparent],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectFromPointerOrKeyboard(_SettingsSection section) {
    _select(
      section,
      keyboard:
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional,
    );
  }

  void _select(_SettingsSection section, {required bool keyboard}) {
    if (section == _section) return;
    setState(() {
      _section = section;
      _instantSwitch = keyboard;
    });
    if (!keyboard) return;
    // Keyboard moves follow the selection: focus and scroll the new item in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navFocus[section]?.requestFocus();
      final itemContext = _navItemKeys[section]?.currentContext;
      if (itemContext != null) {
        Scrollable.ensureVisible(
          itemContext,
          alignment: 0.5,
          duration: FrameMotion.instant,
        );
      }
    });
  }

  /// Up and down move the selection through the sections in display order.
  KeyEventResult _handleNavKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    final strings = ref.read(appStringsProvider);
    final order = [for (final group in _navGroups(strings)) ...group.$2];
    final index = order.indexOf(_section);
    final target = (index + step).clamp(0, order.length - 1);
    _select(order[target], keyboard: true);
    return KeyEventResult.handled;
  }

  /// A run counts as active from the first working state until it settles.
  bool _isRunActive(AgentStatus? status) => switch (status) {
    AgentStatus.working ||
    AgentStatus.retrying ||
    AgentStatus.compacting ||
    AgentStatus.awaitingUser => true,
    _ => false,
  };

  FrameStatusTone _runStatusTone(AgentStatus status) => switch (status) {
    AgentStatus.idle => FrameStatusTone.neutral,
    AgentStatus.settled => FrameStatusTone.success,
    AgentStatus.working ||
    AgentStatus.retrying ||
    AgentStatus.compacting => FrameStatusTone.info,
    AgentStatus.awaitingUser => FrameStatusTone.warning,
    AgentStatus.error || AgentStatus.workerError => FrameStatusTone.danger,
  };
}

/// The settings sections. The index order is the one `initialTabIndex`
/// uses (0 = Pi CLI), so callers that pass an index keep working. Privacy
/// lives in Diagnostica (task 8.3), so it has no entry of its own.
enum _SettingsSection {
  piCli,
  packages,
  daemon,
  appearance,
  diagnostics,
  updates,
  terminal,
  remote,
  agents;

  static _SettingsSection fromIndex(int index) {
    final clamped = index.clamp(0, values.length - 1);
    return values[clamped];
  }
}

/// One navigation entry: a label, a selection bar and a rounded hover shape.
/// Vertical items sit in the left column; horizontal items form the narrow
/// tab row and mark the selection with an underline.
class _SettingsNavItem extends StatefulWidget {
  const _SettingsNavItem({
    required this.label,
    required this.name,
    required this.selected,
    required this.vertical,
    required this.focusNode,
    required this.itemKey,
    required this.onTap,
  });

  final String label;
  final String name;
  final bool selected;
  final bool vertical;
  final FocusNode focusNode;
  final GlobalKey itemKey;
  final VoidCallback onTap;

  @override
  State<_SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<_SettingsNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final transparent = tokens.surface.withValues(alpha: 0);
    final background = widget.selected
        ? tokens.surfaceElevated
        : _hovered
        ? tokens.surface
        : transparent;
    final labelStyle = (widget.vertical ? text.body : text.label).copyWith(
      color: widget.selected ? tokens.textPrimary : tokens.textSecondary,
      fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
    );
    final indicator = widget.selected ? tokens.accent : transparent;

    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: labelStyle,
    );

    final body = widget.vertical
        ? Row(
            children: [
              // Accent selection bar on the leading edge.
              AnimatedContainer(
                duration: FrameMotion.micro,
                width: FrameSpace.x1 / 2,
                height: FrameSpace.x4,
                decoration: BoxDecoration(
                  color: indicator,
                  borderRadius: BorderRadius.circular(tokens.radiusPill),
                ),
              ),
              const SizedBox(width: FrameSpace.x2),
              Expanded(child: label),
            ],
          )
        : IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label,
                const SizedBox(height: FrameSpace.x1),
                // Accent selection bar underneath.
                AnimatedContainer(
                  duration: FrameMotion.micro,
                  height: FrameSpace.x1 / 2,
                  decoration: BoxDecoration(
                    color: indicator,
                    borderRadius: BorderRadius.circular(tokens.radiusPill),
                  ),
                ),
              ],
            ),
          );

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          key: ValueKey('settings-nav-${widget.name}'),
          focusNode: widget.focusNode,
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          hoverColor: transparent,
          highlightColor: tokens.surfaceElevated,
          child: AnimatedContainer(
            key: widget.itemKey,
            duration: FrameMotion.micro,
            constraints: const BoxConstraints(minHeight: FrameSize.rowList),
            padding: const EdgeInsets.symmetric(
              horizontal: FrameSpace.x2,
              vertical: FrameSpace.x1,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}
