import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_chrome.dart';
import '../ui/precision.dart';
import '../data/daemon/daemon_providers.dart';
import '../data/daemon/pcp_client.dart';
import '../data/theme/theme_providers.dart';
import '../features/sessions_sidebar/sessions_sidebar.dart';
import '../features/sessions_sidebar/session_actions.dart';
import '../features/transcript/transcript_view.dart';
import '../features/transcript/chat_drop_target.dart';
import '../features/composer/composer.dart';
import '../features/context_panel/context_panel.dart';
import '../features/workspace/repository_workspace.dart';
import '../features/command_palette/command_palette.dart';
import '../features/settings/settings_view.dart';
import '../data/notifications/notification_providers.dart';
import '../data/notifications/session_notification_watcher.dart';
import '../features/settings/updates_watcher.dart';
import '../data/update/update_providers.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WindowListener, WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _closingWindow = false;
  late final bool _handlesNativeClose;
  late final bool _hasWindowListener;
  bool _creating = false;
  WorkspacePane _compactPane = WorkspacePane.chat;
  WorkspacePane _companionPane = WorkspacePane.repository;
  final Map<WorkspacePane, bool> _paneVisibility = {
    WorkspacePane.repository: true,
    WorkspacePane.chat: true,
    WorkspacePane.git: true,
  };
  final Map<WorkspacePane, double> _paneWeights = {
    WorkspacePane.repository: 32,
    WorkspacePane.chat: 44,
    WorkspacePane.git: 24,
  };
  final Set<WorkspacePane> _collapsedPanes = {};
  final Map<WorkspacePane, double> _savedPaneWeights = {
    WorkspacePane.repository: 32,
    WorkspacePane.chat: 44,
    WorkspacePane.git: 24,
  };
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final desktopLifecycle = ref.read(desktopWindowLifecycleProvider);
    _handlesNativeClose =
        desktopLifecycle && !ref.read(desktopChromeProvider);
    _hasWindowListener = desktopLifecycle;
    if (_hasWindowListener) {
      windowManager.addListener(this);
      if (_handlesNativeClose) {
        unawaited(windowManager.setPreventClose(true));
      }
    }
  }

  @override
  void onWindowFocus() {
    ref.read(appFocusProvider.notifier).state = true;
  }

  @override
  void onWindowBlur() {
    ref.read(appFocusProvider.notifier).state = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appFocusProvider.notifier).state = true;
    } else {
      ref.read(appFocusProvider.notifier).state = false;
    }
  }

  @override
  void onWindowClose() async {
    if (_closingWindow || !_handlesNativeClose) return;
    _closingWindow = true;
    try {
      final allowClose = await resolveDirtyRepository(
        context,
        ref,
        ref.read(activeSessionIdProvider),
      );
      if (!mounted || !allowClose) return;
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } finally {
      _closingWindow = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_hasWindowListener) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  void _palette() => CommandPalette.show(
    context,
    onOpenSettings: () => ref.read(showSettingsProvider.notifier).state = true,
  );
  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    await createSession(context, ref);
    if (mounted) setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final activeId = ref.watch(activeSessionIdProvider);
    final settings = ref.watch(showSettingsProvider);
    final connection =
        ref.watch(connectionStateProvider).value ??
        DaemonConnectionState.disconnected;
    final connected = connection == DaemonConnectionState.connected;
    final width = MediaQuery.sizeOf(context).width;
    final showSessionRail = width >= 1560;
    final nativeChrome = ref.watch(desktopChromeProvider);
    Widget workArea() => activeId == null
        ? _welcome(tokens, !showSessionRail, connected)
        : ChatDropTarget(
            key: ValueKey('chat_drop_target_$activeId'),
            sessionId: activeId,
            child: Column(
              children: [
                Expanded(
                  child: TranscriptView(
                    key: ValueKey('transcript_$activeId'),
                    sessionId: activeId,
                  ),
                ),
                Composer(
                  key: ValueKey('composer_$activeId'),
                  sessionId: activeId,
                ),
              ],
            ),
          );

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyK &&
            (HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isControlPressed)) {
          _palette();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: tokens.background,
        drawer: Drawer(
          width: 280,
          child: SessionsSidebar(
            onSessionSelected: () => _scaffoldKey.currentState?.closeDrawer(),
          ),
        ),
        endDrawer: activeId == null
            ? null
            : Drawer(
                width: width < 420 ? width - 24 : 320,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Area di lavoro',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Chiudi workspace',
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  _scaffoldKey.currentState?.closeEndDrawer(),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ContextPanel(
                          key: ValueKey('drawer-context_$activeId'),
                          sessionId: activeId,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        body: Stack(
          children: [
            const SessionNotificationWatcher(),
            const UpdatesPeriodicWatcher(),
            SafeArea(
              child: Column(
            children: [
              Container(
                height: 76,
                margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                decoration: BoxDecoration(
                  color: tokens.chassis,
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                  border: Border.all(color: tokens.border),
                ),
                child: Row(
                  children: [
                    if (!showSessionRail)
                      IconButton(
                        tooltip: 'Apri sessioni',
                        icon: const Icon(Icons.menu),
                        onPressed: () =>
                            _scaffoldKey.currentState?.openDrawer(),
                      ),
                    Expanded(
                      child: DesktopDragRegion(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: showSessionRail ? 24 : 4,
                          ),
                          child: Row(
                            children: [
                              const CrustMark(size: 28),
                              const SizedBox(width: 12),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: BrandWordmark(size: width < 520 ? 30 : 38),
                                ),
                              ),
                              if (width > 920) ...[
                                const SizedBox(width: 32),
                                Icon(
                                  connected ? Icons.link : Icons.link_off,
                                  size: 16,
                                  color: tokens.textPrimary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  connected ? 'Pi locale' : 'Non connesso',
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (width > 680)
                      PressFeedback(
                        child: TextButton.icon(
                          onPressed: _palette,
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('Comandi'),
                        ),
                      ),
                    if (width >= 900 && activeId != null && !settings)
                      PopupMenuButton<WorkspacePane>(
                        tooltip: 'Mostra o nascondi pannelli',
                        onSelected: _togglePane,
                        itemBuilder: (context) => [
                          for (final pane in WorkspacePane.values)
                            PopupMenuItem(
                              value: pane,
                              child: Row(
                                children: [
                                  Icon(
                                    _paneVisibility[pane] == true
                                        ? Icons.check_box_outlined
                                        : Icons.check_box_outline_blank,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_paneLabel(pane)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    IconButton(
                      visualDensity: width < 400 ? VisualDensity.compact : VisualDensity.standard,
                      padding: width < 400 ? EdgeInsets.zero : const EdgeInsets.all(8.0),
                      constraints: width < 400 ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
                      tooltip: Theme.of(context).brightness == Brightness.light
                          ? 'Tema scuro'
                          : 'Tema chiaro',
                      icon: Icon(
                        Theme.of(context).brightness == Brightness.light
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        size: 18,
                      ),
                      onPressed: () => ref
                          .read(activeThemeSpecProvider.notifier)
                          .setTheme(
                            Theme.of(context).brightness == Brightness.light
                                ? 'crust-dark'
                                : 'crust-light',
                          ),
                    ),
                    IconButton(
                      visualDensity: width < 400 ? VisualDensity.compact : VisualDensity.standard,
                      padding: width < 400 ? EdgeInsets.zero : const EdgeInsets.all(8.0),
                      constraints: width < 400 ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
                      tooltip: 'Impostazioni',
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.settings_outlined, size: 18),
                          if (ref.watch(hasUpdateBadgeProvider))
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: tokens.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      onPressed: () =>
                          ref.read(showSettingsProvider.notifier).state =
                              !settings,
                    ),
                    if (activeId != null && !settings)
                      IconButton(
                        visualDensity: width < 400 ? VisualDensity.compact : VisualDensity.standard,
                        padding: width < 400 ? EdgeInsets.zero : const EdgeInsets.all(8.0),
                        constraints: width < 400 ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
                        tooltip: 'Modello e azioni sessione',
                        icon: const Icon(Icons.tune, size: 19),
                        onPressed: () =>
                            _scaffoldKey.currentState?.openEndDrawer(),
                      ),
                    if (nativeChrome) ...[
                      Container(
                        width: 1,
                        height: 30,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: tokens.borderStrong,
                      ),
                      DesktopCaptionButtons(
                        onCloseRequested: () =>
                            resolveDirtyRepository(context, ref, activeId),
                      ),
                    ] else
                      const SizedBox(width: 12),
                  ],
                ),
              ),
              if (!connected)
                Container(
                  color: tokens.signalWarning.withValues(alpha: 0.16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link_off, size: 17, color: tokens.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          connection == DaemonConnectionState.reconnecting
                              ? 'Riconnessione al daemon in corso...'
                              : 'Daemon non raggiungibile. Le sessioni restano gestite da Pi.',
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.textPrimary,
                        ),
                        onPressed: () => ref.invalidate(daemonEndpointProvider),
                        child: const Text('Riprova'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: settings
                    ? SettingsView(
                        onClose: () =>
                            ref.read(showSettingsProvider.notifier).state =
                                false,
                      )
                    : Row(
                        children: [
                          if (showSessionRail)
                            _sidebarCollapsed
                                ? _collapsedSidebarStrip(tokens)
                                : _bentoPane(
                                    SizedBox(
                                      width: 280,
                                      child: SessionsSidebar(
                                        onCollapse: () => setState(
                                          () => _sidebarCollapsed = true,
                                        ),
                                      ),
                                    ),
                                  ),
                          Expanded(
                            child: activeId == null
                                ? RepaintBoundary(child: workArea())
                                : _workspace(activeId, width, workArea),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    ),
      ),
    );
  }

  Widget _workspace(String sessionId, double width, Widget Function() chat) {
    final panes = <WorkspacePane, Widget>{
      WorkspacePane.repository: RepositoryPane(
        key: ValueKey('repo_$sessionId'),
        sessionId: sessionId,
        onCollapse: () => _collapsePane(WorkspacePane.repository),
      ),
      WorkspacePane.chat: chat(),
      WorkspacePane.git: GitChangesPane(
        key: ValueKey('git_$sessionId'),
        sessionId: sessionId,
        onCollapse: () => _collapsePane(WorkspacePane.git),
      ),
    };
    final visible = _visiblePanes(chatFirst: width < 900);

    if (width < 900) {
      final selected = visible.contains(_compactPane)
          ? _compactPane
          : visible.first;
      return Column(
        children: [
          _paneSelector(
            visible,
            selected,
            (pane) => setState(() => _compactPane = pane),
            showLayoutMenu: true,
          ),
          Expanded(
            child: IndexedStack(
              index: visible.indexOf(selected),
              children: [for (final pane in visible) _bentoPane(panes[pane]!)],
            ),
          ),
        ],
      );
    }

    if (width < 1440 && _paneVisibility[WorkspacePane.chat] == true) {
      final companions = visible
          .where((pane) => pane != WorkspacePane.chat)
          .toList();
      if (companions.isNotEmpty) {
        final selected = companions.contains(_companionPane)
            ? _companionPane
            : companions.first;
        return Column(
          children: [
            if (companions.length > 1)
              _paneSelector(
                companions,
                selected,
                (pane) => setState(() => _companionPane = pane),
              ),
            Expanded(
              child: _resizablePaneRow([WorkspacePane.chat, selected], panes),
            ),
          ],
        );
      }
    }

    return _resizablePaneRow(visible, panes);
  }

  List<WorkspacePane> _visiblePanes({bool chatFirst = false}) {
    final order = chatFirst
        ? WorkspacePane.values
        : const [
            WorkspacePane.repository,
            WorkspacePane.chat,
            WorkspacePane.git,
          ];
    return order.where((pane) => _paneVisibility[pane] == true).toList();
  }

  String _paneLabel(WorkspacePane pane) => switch (pane) {
    WorkspacePane.chat => 'Chat',
    WorkspacePane.repository => 'Repository',
    WorkspacePane.git => 'Git Changes',
  };

  void _togglePane(WorkspacePane pane) {
    final visible = _visiblePanes();
    if (_paneVisibility[pane] == true && visible.length <= 1) return;
    setState(() {
      final nowVisible = !(_paneVisibility[pane] ?? false);
      _paneVisibility[pane] = nowVisible;
      if (nowVisible) {
        _collapsedPanes.remove(pane);
      }
      final remaining = _visiblePanes();
      if (!remaining.contains(_compactPane)) _compactPane = remaining.first;
      if (!remaining.contains(_companionPane)) {
        _companionPane = remaining.firstWhere(
          (item) => item != WorkspacePane.chat,
          orElse: () => remaining.first,
        );
      }
    });
  }

  Widget _bentoPane(Widget child) {
    final tokens = context.tokens;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          child: child,
        ),
      ),
    );
  }

  void _collapsePane(WorkspacePane pane) {
    final visible = _visiblePanes();
    final openPanes =
        visible.where((p) => !_collapsedPanes.contains(p)).toList();
    if (openPanes.length <= 1) return; // Always keep at least one pane open

    setState(() {
      _savedPaneWeights[pane] = _paneWeights[pane] ?? 30;
      _collapsedPanes.add(pane);

      final remaining = openPanes.where((p) => p != pane).toList();
      if (remaining.isNotEmpty) {
        final freed = _paneWeights[pane] ?? 30;
        final extra = freed / remaining.length;
        for (final rem in remaining) {
          _paneWeights[rem] = (_paneWeights[rem] ?? 30) + extra;
        }
      }
    });
  }

  void _expandPane(WorkspacePane pane) {
    if (!_collapsedPanes.contains(pane)) return;
    setState(() {
      _collapsedPanes.remove(pane);
      final visible = _visiblePanes();
      final openOthers = visible
          .where((p) => p != pane && !_collapsedPanes.contains(p))
          .toList();

      final restoreWeight = (_savedPaneWeights[pane] ?? 30).clamp(15.0, 50.0);
      _paneWeights[pane] = restoreWeight;

      if (openOthers.isNotEmpty) {
        final totalOther = openOthers.fold<double>(
          0.0,
          (sum, p) => sum + (_paneWeights[p] ?? 30),
        );
        final targetOther = (100.0 - restoreWeight).clamp(20.0, 85.0);
        final factor =
            totalOther > 0 ? targetOther / totalOther : 1.0;
        for (final other in openOthers) {
          _paneWeights[other] =
              ((_paneWeights[other] ?? 30) * factor).clamp(10.0, 85.0);
        }
      }
    });
  }

  Widget _collapsedPaneStrip(WorkspacePane pane) {
    final tokens = context.tokens;
    final isLeft = pane == WorkspacePane.repository;
    final iconData = switch (pane) {
      WorkspacePane.repository => Icons.folder_outlined,
      WorkspacePane.git => Icons.source_outlined,
      WorkspacePane.chat => Icons.chat_bubble_outline,
    };
    final expandIcon = isLeft ? Icons.chevron_right : Icons.chevron_left;
    final label = _paneLabel(pane).toUpperCase();

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          width: 34,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          child: Column(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: 'Espandi pannello ${_paneLabel(pane)}',
                icon: Icon(expandIcon, size: 18, color: tokens.accent),
                onPressed: () => _expandPane(pane),
              ),
              const SizedBox(height: 6),
              Icon(iconData, size: 15, color: tokens.textMuted),
              const SizedBox(height: 12),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _collapsedSidebarStrip(CrustTokens tokens) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          width: 36,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          child: Column(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                tooltip: 'Espandi barra sessioni',
                icon: Icon(Icons.chevron_right, size: 18, color: tokens.accent),
                onPressed: () => setState(() => _sidebarCollapsed = false),
              ),
              const SizedBox(height: 8),
              const CrustMark(size: 20),
              const SizedBox(height: 12),
              Icon(Icons.chat_bubble_outline, size: 15, color: tokens.textMuted),
              const SizedBox(height: 12),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Center(
                    child: Text(
                      'SESSIONI',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resizablePaneRow(
    List<WorkspacePane> panes,
    Map<WorkspacePane, Widget> contents,
  ) {
    if (panes.isEmpty) return const SizedBox.shrink();
    if (panes.length == 1 && _collapsedPanes.isEmpty) {
      return _bentoPane(contents[panes.single]!);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 8.0;
        final collapsedCount =
            panes.where((p) => _collapsedPanes.contains(p)).length;
        const collapsedWidth = 40.0;
        final availableWidth = constraints.maxWidth -
            dividerWidth * (panes.length - 1) -
            (collapsedWidth * collapsedCount);

        return Row(
          children: [
            for (var index = 0; index < panes.length; index++) ...[
              if (_collapsedPanes.contains(panes[index]))
                _collapsedPaneStrip(panes[index])
              else
                Expanded(
                  flex: (_paneWeights[panes[index]] ?? 1)
                      .round()
                      .clamp(1, 100)
                      .toInt(),
                  child: _bentoPane(contents[panes[index]]!),
                ),
              if (index < panes.length - 1)
                MouseRegion(
                  key: ValueKey(
                    'pane-divider-${panes[index]}-${panes[index + 1]}',
                  ),
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) => _resizeAdjacent(
                      panes[index],
                      panes[index + 1],
                      details.delta.dx,
                      availableWidth,
                    ),
                    child: SizedBox(
                      width: dividerWidth,
                      child: Center(
                        child: Container(
                          width: 1,
                          height: 40,
                          color: context.tokens.borderStrong,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  void _resizeAdjacent(
    WorkspacePane left,
    WorkspacePane right,
    double delta,
    double availableWidth,
  ) {
    if (_collapsedPanes.contains(left)) {
      if (delta > 6) {
        _expandPane(left);
      }
      return;
    }
    if (_collapsedPanes.contains(right)) {
      if (delta < -6) {
        _expandPane(right);
      }
      return;
    }

    final leftWeight = _paneWeights[left] ?? 1;
    final rightWeight = _paneWeights[right] ?? 1;
    final total = leftWeight + rightWeight;
    if (availableWidth <= 0 || total <= 0) return;

    final minimum = total * 0.15;
    final candidateLeft = leftWeight + delta / availableWidth * total;

    final openCount =
        _visiblePanes().where((p) => !_collapsedPanes.contains(p)).length;
    if (openCount > 1) {
      if (candidateLeft < minimum) {
        _collapsePane(left);
        return;
      }
      if (total - candidateLeft < minimum) {
        _collapsePane(right);
        return;
      }
    }

    final nextLeft = candidateLeft.clamp(minimum, total - minimum).toDouble();
    setState(() {
      _paneWeights[left] = nextLeft;
      _paneWeights[right] = total - nextLeft;
    });
  }

  Widget _paneSelector(
    List<WorkspacePane> panes,
    WorkspacePane selected,
    ValueChanged<WorkspacePane> onSelected, {
    bool showLayoutMenu = false,
  }) {
    final tokens = context.tokens;
    String label(WorkspacePane pane) => switch (pane) {
      WorkspacePane.chat => 'Chat',
      WorkspacePane.repository => 'File',
      WorkspacePane.git => 'Git Changes',
    };
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.chassis,
        border: Border(bottom: BorderSide(color: tokens.borderStrong)),
      ),
      child: Row(
        children: [
          for (final pane in panes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Semantics(
                  button: true,
                  selected: pane == selected,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      foregroundColor: pane == selected
                          ? tokens.displayText
                          : tokens.textPrimary,
                      backgroundColor: pane == selected
                          ? tokens.displaySurface
                          : tokens.chassis,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        side: BorderSide(
                          color: pane == selected
                              ? tokens.borderStrong
                              : tokens.border,
                        ),
                      ),
                    ),
                    onPressed: () => onSelected(pane),
                    child: Text(
                      label(pane),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          if (showLayoutMenu)
            PopupMenuButton<WorkspacePane>(
              tooltip: 'Mostra o nascondi pannelli',
              onSelected: _togglePane,
              itemBuilder: (context) => [
                for (final pane in WorkspacePane.values)
                  PopupMenuItem(
                    value: pane,
                    child: Row(
                      children: [
                        Icon(
                          _paneVisibility[pane] == true
                              ? Icons.check_box_outlined
                              : Icons.check_box_outline_blank,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(_paneLabel(pane)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _welcome(CrustTokens tokens, bool narrow, bool connected) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 580;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.all(compact ? 28 : 56),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CrustMark(size: compact ? 48 : 64),
                    const SizedBox(height: 32),
                    Text(
                      'Nuova\nsessione.',
                      style: TextStyle(
                        fontFamily: tokens.headingFontFamily,
                        fontSize: compact ? 68 : 96,
                        height: 0.95,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.0,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Text(
                        'Scegli una conversazione o inizia a lavorare con Pi. Il lavoro continua anche quando chiudi la finestra.',
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        PressFeedback(
                          child: FilledButton.icon(
                            onPressed: connected && !_creating ? _create : null,
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(
                              _creating ? 'Creazione...' : 'Nuova sessione',
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: narrow
                              ? () => _scaffoldKey.currentState?.openDrawer()
                              : _palette,
                          icon: const Icon(Icons.search, size: 18),
                          label: Text(
                            narrow ? 'Esplora sessioni' : 'Cerca nei comandi',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Text(
                      'Ctrl / Cmd + K · Comandi',
                      style: TextStyle(color: tokens.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
