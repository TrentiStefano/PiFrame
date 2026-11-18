import 'dart:async';
import 'dart:math' as math;

import '../ui/escape_layers.dart';
import '../ui/frame_focus.dart';
import '../ui/frame_icon_action.dart';
import '../ui/motion.dart';
import '../ui/phone_corners.dart';
import 'focus_regions.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_chrome.dart';
import '../ui/precision.dart';
import '../data/daemon/daemon_providers.dart';
import '../data/daemon/pcp_client.dart';
import '../data/language/language_settings.dart';
import '../data/language/strings_shell.dart';
import '../data/language/strings_workspace.dart';
import '../data/theme/theme_providers.dart';
import '../features/sessions_sidebar/session_actions.dart';
import '../features/sessions_sidebar/sessions_sidebar.dart';
import '../features/sessions_sidebar/unread_sessions_provider.dart';
import '../features/transcript/transcript_view.dart';
import '../features/transcript/subagent_panel.dart';
import '../features/transcript/chat_drop_target.dart';
import '../features/composer/composer.dart';
import '../features/context_panel/context_panel.dart';
import '../features/workspace/pane_drag_state.dart';
import '../features/workspace/repository_workspace.dart';
import '../features/browser/browser_models.dart';
import '../features/browser/browser_controller.dart';
import '../features/browser/web_browser_pane.dart';
import '../features/command_palette/command_palette.dart';
import '../features/settings/settings_view.dart';
import '../features/welcome/welcome_view.dart';
import '../data/notifications/notification_providers.dart';
import '../data/notifications/session_notification_watcher.dart';
import '../features/settings/updates_watcher.dart';
import '../data/update/update_providers.dart';
import '../features/session_changes/session_changes_provider.dart';
import '../features/session_changes/session_changes_pane.dart';
import '../data/pi_install/pi_install_service.dart';
import '../features/dialogs/pi_install_dialog.dart';
import '../features/side/side_provider.dart';
import '../data/metrics/nerd_stats_settings.dart';
import '../data/metrics/system_metrics_controller.dart';
import '../features/metrics/nerd_stats_bar.dart';
import '../features/updates/startup_update_banner.dart';
import '../features/updates/startup_updates_watcher.dart';
import '../data/window/window_state_service.dart';
import '../data/layout/layout_store.dart';

/// Minimum width of a companion pane (repository, git or browser). Narrower, and
/// the companion collapses to its tab (audit R2 / plan task 1.2f).
const double kCompanionMinWidth = 160;

/// Companion panes whose share of [availableWidth] would be narrower than
/// [kCompanionMinWidth]. Only applies while another pane stays open, so the last
/// visible pane is never hidden. The chat pane is never a companion.
Set<WorkspacePane> narrowCompanionPanes({
  required List<WorkspacePane> panes,
  required Set<WorkspacePane> collapsed,
  required Map<WorkspacePane, int> weights,
  required double availableWidth,
  double minWidth = kCompanionMinWidth,
}) {
  final open = panes.where((p) => !collapsed.contains(p)).toList();
  if (open.length < 2) return <WorkspacePane>{};
  final totalWeight = open.fold<int>(0, (sum, p) => sum + (weights[p] ?? 1));
  if (totalWeight <= 0) return <WorkspacePane>{};
  return {
    for (final p in open)
      if (p != WorkspacePane.chat &&
          availableWidth * (weights[p] ?? 1) / totalWeight < minWidth)
        p,
  };
}

/// Minimum width of the chat pane when the layout is restored (plan task 6.6).
const double kChatMinWidth = 420;

/// Window width from which the sessions rail is docked beside the panes.
const double kSessionRailMinWidth = 1560;

/// Clamps restored pane weights so that every open companion is at least
/// [kCompanionMinWidth] wide and the chat pane at least [kChatMinWidth]. Pinned panes
/// keep their minimum share; the other open panes share what is left, in proportion.
/// Returns weights summing to 100 over the open panes. A single open pane is untouched.
Map<WorkspacePane, double> clampRestoredPaneWeights({
  required List<WorkspacePane> panes,
  required Set<WorkspacePane> collapsed,
  required Map<WorkspacePane, double> weights,
  required double availableWidth,
}) {
  final result = {for (final p in panes) p: weights[p] ?? 1.0};
  final open = panes.where((p) => !collapsed.contains(p)).toList();
  if (open.length < 2 || availableWidth <= 0) return result;
  // Flex weights are rounded to whole numbers when laid out, so each minimum gets a
  // small margin; otherwise a pane could land a few pixels under its minimum.
  double minShare(WorkspacePane p) =>
      (p == WorkspacePane.chat ? kChatMinWidth : kCompanionMinWidth) *
      1.03 /
      availableWidth;

  final pinned = <WorkspacePane, double>{};
  var changed = true;
  while (changed) {
    changed = false;
    final free = open.where((p) => !pinned.containsKey(p)).toList();
    final freeTotal = free.fold<double>(0, (sum, p) => sum + result[p]!);
    final budget = 1.0 - pinned.values.fold<double>(0, (sum, v) => sum + v);
    for (final p in free) {
      final share = freeTotal > 0
          ? result[p]! / freeTotal * budget
          : budget / free.length;
      if (share < minShare(p)) {
        pinned[p] = minShare(p);
        changed = true;
      }
    }
  }

  final freeTotal = open
      .where((p) => !pinned.containsKey(p))
      .fold<double>(0, (sum, p) => sum + result[p]!);
  final budget = 1.0 - pinned.values.fold<double>(0, (sum, v) => sum + v);
  for (final p in open) {
    final share =
        pinned[p] ?? (freeTotal > 0 ? result[p]! / freeTotal * budget : budget);
    result[p] = share * 100;
  }
  return result;
}

WorkspacePane? _paneNamed(Object? name) {
  for (final pane in WorkspacePane.values) {
    if (pane.name == name) return pane;
  }
  return null;
}

/// Below this window width the title bar shows the connection dot without its label
/// (plan task 5.4). The dot keeps a tooltip and a semantic label.
const double kConnectionLabelMinWidth = 920;

/// Window width from which the context drawer button shows its label "Sessione" (plan
/// task 5.4); below it the button is icon-only.
const double kContextDrawerLabelMinWidth = 1100;

/// Title bar connection status (plan task 5.4): a dot, with the label from
/// [kConnectionLabelMinWidth] up. A click opens Diagnostics in Settings.
class _ConnectionIndicator extends StatelessWidget {
  const _ConnectionIndicator({
    required this.connected,
    required this.label,
    required this.tooltip,
    required this.showLabel,
    required this.onTap,
  });

  final bool connected;
  final String label;
  final String tooltip;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey('shell-connection-indicator'),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: FrameSize.hitMin,
              minHeight: FrameSize.hitMin,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: FrameSpace.x2),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: connected ? tokens.success : tokens.warning,
                    shape: BoxShape.circle,
                  ),
                ),
                if (showLabel) ...[
                  const SizedBox(width: FrameSpace.x2),
                  Text(
                    label,
                    style: FrameText.of(context).caption
                        .copyWith(color: tokens.textMuted),
                  ),
                ],
                const SizedBox(width: FrameSpace.x2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keyboard and screen-reader access for every resizable divider (plan task 6.7): the
/// divider takes focus, ←/→ move it one step (the same step the Semantics actions use),
/// and the increase/decrease actions are exposed. The caller owns the drag gestures.
class _ResizeDividerFocus extends StatefulWidget {
  const _ResizeDividerFocus({
    required this.label,
    required this.value,
    required this.builder,
    this.increasedValue,
    this.decreasedValue,
    this.onIncrease,
    this.onDecrease,
  });

  final String label;
  final String value;
  final String? increasedValue;
  final String? decreasedValue;
  // Null when the divider cannot move further in that direction.
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;
  final Widget Function(BuildContext context, bool focused) builder;

  @override
  State<_ResizeDividerFocus> createState() => _ResizeDividerFocusState();
}

class _ResizeDividerFocusState extends State<_ResizeDividerFocus> {
  bool _focused = false;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        widget.onDecrease != null) {
      widget.onDecrease!();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        widget.onIncrease != null) {
      widget.onIncrease!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      slider: true,
      label: widget.label,
      value: widget.value,
      // Semantics requires both or neither: fall back to the current value.
      increasedValue: widget.increasedValue ?? widget.value,
      decreasedValue: widget.decreasedValue ?? widget.value,
      onIncrease: widget.onIncrease,
      onDecrease: widget.onDecrease,
      // The ring wraps the Focus, so it shows while the divider has keyboard focus.
      child: FrameFocusRing(
        child: Focus(
          onKeyEvent: _handleKey,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: widget.builder(context, _focused),
        ),
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with
        WindowListener,
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _closingWindow = false;
  late final bool _handlesNativeClose;
  late final bool _hasWindowListener;
  bool _creating = false;
  int _settingsEpoch = 0;
  // Section id for the next Settings open; null means the tab index provider decides.
  String? _settingsSection;
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
  // Pane width transition (task 7.3). Show, hide, collapse and expand from the
  // title bar or strips animate the slot widths from the last displayed layout
  // to the new one. Divider drags, keyboard toggles and palette toggles set
  // no animation. Under reduced motion the layout is final at once and the
  // entering pane cross-fades over _kReducedPaneFade.
  late final AnimationController _paneTransition = AnimationController(
    vsync: this,
  )..addStatusListener(_onPaneTransitionStatus);
  // Slot widths shown in the last pane row, and the snapshot taken when a
  // transition starts. Both keyed by pane.
  Map<WorkspacePane, double> _slotPx = {};
  Map<WorkspacePane, double> _slotFromPx = {};
  // Panes hidden from the title bar that still hold a slot while they shrink,
  // mapped to their index in the previous row.
  final Map<WorkspacePane, int> _exitingPanes = {};
  List<WorkspacePane> _rowOrder = const [];
  bool _paneAnimating = false;
  final Map<WorkspacePane, double> _savedPaneWeights = {
    WorkspacePane.repository: 32,
    WorkspacePane.chat: 44,
    WorkspacePane.git: 24,
  };
  bool _sidebarCollapsed = false;
  // Set when weights are restored; they are clamped on the first pane row with a known width.
  bool _pendingWeightClamp = false;
  // The session that was active before the current one (Ctrl+Tab target).
  String? _previousSessionId;
  Widget? _chatSidecar;
  String? _chatSidecarSessionId;
  // Width of the last pane row, used to size a restored companion (task 1.2f).
  double _rowWidth = 0;
  static const _defaultSidebarWidth = 280.0;
  static const _minimumSidebarWidth = 220.0;
  static const _maximumSidebarWidth = 560.0;
  static const _sidebarDividerWidth = 8.0;
  double _sidebarWidth = _defaultSidebarWidth;
  bool? _preReviewSidebarCollapsed;
  Map<WorkspacePane, bool>? _preReviewPaneVisibility;
  Map<WorkspacePane, double>? _preReviewPaneWeights;
  // Focus regions in Tab order (plan task 6.2). Each key is attached once per build.
  final Map<FocusRegion, GlobalKey> _regionKeys = {
    for (final region in FocusRegion.values) region: GlobalKey(),
  };
  // Escape layers this shell registered (drawers, settings), removed when they close.
  final Map<String, VoidCallback> _escapeHandles = {};

  void _enterReviewMode() {
    _preReviewSidebarCollapsed ??= _sidebarCollapsed;
    _preReviewPaneVisibility ??= Map.from(_paneVisibility);
    _preReviewPaneWeights ??= Map.from(_paneWeights);

    setState(() {
      _sidebarCollapsed = true; // Minimize Sessions pane
      _paneVisibility[WorkspacePane.repository] = false; // Hide Repository pane
      _paneVisibility[WorkspacePane.chat] = true;
      _paneVisibility[WorkspacePane.git] =
          true; // Use Git slot for Review Changes
      _paneWeights[WorkspacePane.chat] = 50.0;
      _paneWeights[WorkspacePane.git] = 50.0;
      _collapsedPanes.remove(WorkspacePane.chat);
      _collapsedPanes.remove(WorkspacePane.git);
    });
  }

  void _exitReviewMode() {
    setState(() {
      if (_preReviewSidebarCollapsed != null) {
        _sidebarCollapsed = _preReviewSidebarCollapsed!;
      }
      if (_preReviewPaneVisibility != null) {
        _paneVisibility.clear();
        _paneVisibility.addAll(_preReviewPaneVisibility!);
      }
      if (_preReviewPaneWeights != null) {
        _paneWeights.clear();
        _paneWeights.addAll(_preReviewPaneWeights!);
      }
      _preReviewSidebarCollapsed = null;
      _preReviewPaneVisibility = null;
      _preReviewPaneWeights = null;
    });
    _persistLayout();
  }

  // Review mode temporarily replaces the layout; persist only the user's own layout.
  void _persistLayout() {
    if (_preReviewPaneVisibility != null) return;
    LayoutStore.instance.save({
      'visibility': {
        for (final pane in WorkspacePane.values)
          pane.name: _paneVisibility[pane] ?? true,
      },
      'sidebarCollapsed': _sidebarCollapsed,
      'sidebarWidth': _sidebarWidth,
      'paneWeights': {
        for (final pane in WorkspacePane.values)
          pane.name: _paneWeights[pane] ?? 1.0,
      },
      'collapsedPanes': [
        for (final pane in WorkspacePane.values)
          if (_collapsedPanes.contains(pane)) pane.name,
      ],
      'compactPane': _compactPane.name,
      'companionPane': _companionPane.name,
    });
  }

  void _selectCompanionPane(WorkspacePane pane) {
    setState(() => _companionPane = pane);
    _persistLayout();
  }

  void _selectCompactPane(WorkspacePane pane) {
    setState(() => _compactPane = pane);
    _persistLayout();
  }

  AppStrings get strings => ref.watch(appStringsProvider);

  // Restores hidden panes after restart; keeps at least one pane visible and the companion valid.
  void _applyPersistedLayout() {
    final saved = LayoutStore.instance.load();
    final visibility = saved['visibility'];
    if (visibility is Map) {
      for (final pane in WorkspacePane.values) {
        final value = visibility[pane.name];
        if (value is bool) _paneVisibility[pane] = value;
      }
    }
    if (saved['sidebarCollapsed'] is bool) {
      _sidebarCollapsed = saved['sidebarCollapsed'] as bool;
    }
    final sidebarWidth = saved['sidebarWidth'];
    if (sidebarWidth is num && sidebarWidth.isFinite) {
      _sidebarWidth = sidebarWidth
          .clamp(_minimumSidebarWidth, _maximumSidebarWidth)
          .toDouble();
    }
    if (!_paneVisibility.containsValue(true)) {
      _paneVisibility[WorkspacePane.chat] = true;
    }
    final weights = saved['paneWeights'];
    if (weights is Map) {
      for (final pane in WorkspacePane.values) {
        final value = weights[pane.name];
        if (value is num && value.isFinite && value > 0) {
          _paneWeights[pane] = value.clamp(1, 100).toDouble();
        }
      }
      // Clamped against the real row width on the first multi-pane build.
      _pendingWeightClamp = true;
    }
    final collapsed = saved['collapsedPanes'];
    if (collapsed is List) {
      _collapsedPanes.clear();
      for (final name in collapsed) {
        final pane = _paneNamed(name);
        if (pane != null && _paneVisibility[pane] == true) {
          _collapsedPanes.add(pane);
        }
      }
      // Never restore a layout with every visible pane collapsed.
      if (_collapsedPanes.length >= _visiblePanes().length) {
        _collapsedPanes.clear();
      }
    }
    final remaining = _visiblePanes();
    final compact = _paneNamed(saved['compactPane']);
    if (compact != null && remaining.contains(compact)) _compactPane = compact;
    if (!remaining.contains(_compactPane)) _compactPane = remaining.first;
    final companion = _paneNamed(saved['companionPane']);
    if (companion != null &&
        companion != WorkspacePane.chat &&
        remaining.contains(companion)) {
      _companionPane = companion;
    }
    if (!remaining.contains(_companionPane)) {
      _companionPane = remaining.firstWhere(
        (item) => item != WorkspacePane.chat,
        orElse: () => remaining.first,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyPersistedLayout();
    final desktopLifecycle = ref.read(desktopWindowLifecycleProvider);
    _handlesNativeClose =
        desktopLifecycle && defaultTargetPlatform != TargetPlatform.windows;
    _hasWindowListener = desktopLifecycle;
    if (_hasWindowListener) {
      windowManager.addListener(this);
      if (_handlesNativeClose) {
        unawaited(windowManager.setPreventClose(true));
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstRunPiInstall();
    });
  }

  Future<void> _checkFirstRunPiInstall() async {
    final service = ref.read(piInstallServiceProvider);
    final isFirst = await service.isFirstRun();
    if (!isFirst || !mounted) return;
    final isInstalled = await service.isPiInstalled();
    if (!isInstalled && mounted) {
      await PiInstallDialog.show(context);
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
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    ref
        .read(activeThemeSpecProvider.notifier)
        .onPlatformBrightnessChanged(
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
        );
  }

  @override
  void onWindowResize() {
    WindowStateService.instance.debounceRecordCurrentState();
  }

  @override
  void onWindowMove() {
    WindowStateService.instance.debounceRecordCurrentState();
  }

  @override
  void onWindowEnterFullScreen() {
    WindowStateService.instance.recordCurrentWindowState();
  }

  @override
  void onWindowLeaveFullScreen() {
    WindowStateService.instance.recordCurrentWindowState();
  }

  @override
  void onWindowMaximize() {
    WindowStateService.instance.recordCurrentWindowState();
  }

  @override
  void onWindowUnmaximize() {
    WindowStateService.instance.recordCurrentWindowState();
  }

  @override
  void onWindowClose() async {
    if (_closingWindow || !_handlesNativeClose) return;
    _closingWindow = true;
    try {
      unawaited(WindowStateService.instance.recordCurrentWindowState());
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
    _paneTransition.dispose();
    if (_hasWindowListener) {
      windowManager.removeListener(this);
    }
    for (final unregister in _escapeHandles.values) {
      unregister();
    }
    _escapeHandles.clear();
    super.dispose();
  }

  /// Registers or removes one of the shell's own Escape layers (plan task 6.3). [tag]
  /// names the layer; a new registration replaces the old one.
  void _setEscapeLayer(
    String tag,
    EscapeLayer layer,
    bool open,
    bool Function() close,
  ) {
    _escapeHandles.remove(tag)?.call();
    if (!open) return;
    _escapeHandles[tag] = ref.read(escapeLayersProvider).register(layer, close);
  }

  /// Focuses the first focusable control of [region] in reading order. Returns false
  /// when the region has nothing to focus (for example, no session is open).
  bool _focusRegion(FocusRegion region) {
    for (final part in region.paneRegions) {
      final nodes = focusableNodesIn(_regionKeys[part]!);
      if (nodes.isEmpty) continue;
      nodes.first.requestFocus();
      return true;
    }
    return false;
  }

  /// F6 and Shift+F6: move focus to the next or previous pane (plan task 6.2).
  void _cyclePane({required bool backwards}) {
    final primary = FocusManager.instance.primaryFocus;
    final panes = FocusRegion.panes;
    final current = panes.indexWhere(
      (pane) => pane.paneRegions.any(
        (part) => focusIsWithin(_regionKeys[part]!, primary),
      ),
    );
    final step = backwards ? -1 : 1;
    var index = current < 0
        ? (backwards ? panes.length - 1 : 0)
        : (current + step + panes.length) % panes.length;
    // Skip panes with nothing to focus (a closed companion, for example).
    for (var attempt = 0; attempt < panes.length; attempt++) {
      if (_focusRegion(panes[index])) return;
      index = (index + step + panes.length) % panes.length;
    }
  }

  /// Opens Settings on Diagnostics (plan task 5.4). [_settingsEpoch] remounts the view,
  /// because a view that is already open keeps its first tab.
  void _openDiagnostics() {
    setState(() {
      _settingsSection = kSettingsSectionDiagnostics;
      _settingsEpoch++;
    });
    ref.read(showSettingsProvider.notifier).state = true;
  }

  void _palette() => CommandPalette.show(
    context,
    ref: ref,
    onOpenSettings: () => ref.read(showSettingsProvider.notifier).state = true,
    isPaneVisible: (pane) => _paneVisibility[pane] == true,
    // Opened from the keyboard: the toggle is instant.
    onTogglePane: (pane) => _togglePane(pane, animate: false),
  );
  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    await createSession(context, ref);
    if (mounted) setState(() => _creating = false);
  }

  /// Shell-level keyboard shortcuts (plan task 6.4). The composer, the editor and the
  /// integrated terminal handle their own keys first, so this only sees keys they leave
  /// unhandled. Ctrl/Cmd+S is not here: editor save belongs to Phase 9.
  KeyEventResult _handleShortcut(KeyEvent event, String? activeId) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final hardware = HardwareKeyboard.instance;
    final commandKey = hardware.isMetaPressed || hardware.isControlPressed;
    final shift = hardware.isShiftPressed;
    final alt = hardware.isAltPressed;
    final key = event.logicalKey;

    // Escape closes the topmost layer (plan task 6.3). Layers that take focus, such as
    // menus and dialogs, close themselves before the key reaches the shell. The composer
    // interrupts a run on Escape only when no layer is open.
    if (key == LogicalKeyboardKey.escape) {
      return ref.read(escapeLayersProvider).closeTopmost()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    // F6 / Shift+F6 move between panes (plan task 6.2).
    if (key == LogicalKeyboardKey.f6 && !commandKey && !alt) {
      _cyclePane(backwards: shift);
      return KeyEventResult.handled;
    }
    // Ctrl/Cmd+1…4 focus sessions, repository, chat and companion (plan task 6.2).
    if (commandKey && !shift && !alt) {
      final number = _pressedDigit(key);
      final region = number == null ? null : FocusRegion.numbered[number];
      if (region != null) {
        return _focusRegion(region)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
    }

    if (key == LogicalKeyboardKey.keyK && commandKey) {
      _palette();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB && commandKey && shift) {
      if (activeId != null) {
        final thread = ref.read(sideThreadFamily(activeId));
        if (!thread.isOpen) {
          ref.read(chatSidecarTabFamily(activeId).notifier).state =
              ChatSidecarTab.side;
        }
        ref
            .read(sideThreadFamily(activeId).notifier)
            .togglePanel(instant: true);
        return KeyEventResult.handled;
      }
    }
    // Ctrl+Tab is the only one that is Ctrl-only; Cmd+Tab belongs to the OS.
    if (key == LogicalKeyboardKey.tab &&
        hardware.isControlPressed &&
        !shift &&
        !alt) {
      _switchToPreviousSession();
      return KeyEventResult.handled;
    }
    if (!commandKey || shift || alt) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.keyN) {
      unawaited(_create());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.comma) {
      ref.read(showSettingsProvider.notifier).state = true;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      _toggleSessionsRail();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Shows or hides the sessions rail when it is docked; otherwise opens or closes the drawer.
  void _toggleSessionsRail() {
    final docked = MediaQuery.sizeOf(context).width >= kSessionRailMinWidth;
    if (docked) {
      setState(() => _sidebarCollapsed = !_sidebarCollapsed);
      _persistLayout();
      return;
    }
    final scaffold = _scaffoldKey.currentState;
    if (scaffold == null) return;
    if (scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
    } else {
      scaffold.openDrawer();
    }
  }

  /// The digit 1…4 of a top-row digit key, or null for any other key.
  int? _pressedDigit(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.digit1) return 1;
    if (key == LogicalKeyboardKey.digit2) return 2;
    if (key == LogicalKeyboardKey.digit3) return 3;
    if (key == LogicalKeyboardKey.digit4) return 4;
    return null;
  }

  /// Switches back to the session that was active before the current one, if it still exists.
  void _switchToPreviousSession() {
    final target = _previousSessionId;
    if (target == null || target == ref.read(activeSessionIdProvider)) return;
    final listed = ref.read(sessionListProvider).value;
    if (listed != null && !listed.any((session) => session['id'] == target)) {
      return;
    }
    ref.read(activeSessionIdProvider.notifier).state = target;
  }

  @override
  Widget build(BuildContext context) {
    // Keeps unread tracking alive while the sessions rail is hidden.
    ref.listen(unreadSessionsProvider, (_, _) {});
    ref.listen<bool>(isReviewingChangesProvider, (prev, next) {
      if (next) {
        _enterReviewMode();
      } else {
        _exitReviewMode();
      }
    });
    ref.listen<String?>(activeSessionIdProvider, (prev, next) {
      if (prev != null && next != null && prev != next) {
        _previousSessionId = prev;
      }
    });
    ref.listen<bool>(showSettingsProvider, (prev, next) {
      // Closing Settings forgets the section, so a later plain open uses the tab index.
      if (!next) {
        _settingsSection = null;
      }
      _setEscapeLayer('settings', EscapeLayer.settings, next, () {
        final wasOpen = ref.read(showSettingsProvider);
        ref.read(showSettingsProvider.notifier).state = false;
        return wasOpen;
      });
    });

    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final activeId = ref.watch(activeSessionIdProvider);
    final settings = ref.watch(showSettingsProvider);
    final connection =
        ref.watch(connectionStateProvider).value ??
        DaemonConnectionState.disconnected;
    final connected = connection == DaemonConnectionState.connected;
    final connectionLabel = connected ? strings.localPi : strings.disconnected;
    final width = MediaQuery.sizeOf(context).width;
    final showSessionRail = width >= kSessionRailMinWidth;
    final bannerInRail = showSessionRail && !_sidebarCollapsed && !settings;
    final nativeChrome = ref.watch(desktopChromeProvider);
    Widget workArea() => activeId == null
        ? WelcomeView(
            narrow: !showSessionRail,
            connected: connected,
            onOpenSessionsDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            onOpenCommandPalette: _palette,
          )
        : ChatDropTarget(
            key: ValueKey('chat_drop_target_$activeId'),
            sessionId: activeId,
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  Expanded(
                    child: FocusRegionMarker(
                      region: FocusRegion.transcript,
                      regionKey: _regionKeys[FocusRegion.transcript]!,
                      child: TranscriptView(
                        key: ValueKey('transcript_$activeId'),
                        sessionId: activeId,
                      ),
                    ),
                  ),
                  FocusRegionMarker(
                    region: FocusRegion.composer,
                    regionKey: _regionKeys[FocusRegion.composer]!,
                    child: Composer(
                      key: ValueKey('composer_$activeId'),
                      sessionId: activeId,
                      availableHeight: constraints.maxHeight,
                    ),
                  ),
                ],
              ),
            ),
          );

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Focus(
        autofocus: true,
        // Only receives keys when nothing inside has focus; it is not a Tab stop.
        skipTraversal: true,
        onKeyEvent: (_, event) => _handleShortcut(event, activeId),
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: tokens.background,
          onDrawerChanged: (open) => _setEscapeLayer(
            'drawer',
            EscapeLayer.drawer,
            open,
            () {
              final wasOpen = _scaffoldKey.currentState?.isDrawerOpen ?? false;
              _scaffoldKey.currentState?.closeDrawer();
              return wasOpen;
            },
          ),
          onEndDrawerChanged: (open) =>
              _setEscapeLayer('endDrawer', EscapeLayer.drawer, open, () {
                final wasOpen =
                    _scaffoldKey.currentState?.isEndDrawerOpen ?? false;
                _scaffoldKey.currentState?.closeEndDrawer();
                return wasOpen;
              }),
          drawer: Drawer(
            width:
                _effectiveSidebarWidth(width, inDrawer: true) +
                _sidebarDividerWidth,
            child: _sessionsSidebar(width, inDrawer: true),
          ),
          endDrawer: activeId == null
              ? null
              : Drawer(
                  width: width < 420 ? width - 24 : 320,
                  // The panel draws its own heading. Escape and a tap on the scrim close it
                  // (plan task 6.3), so the shell adds no heading or close button here.
                  child: SafeArea(
                    child: ContextPanel(
                      key: ValueKey('drawer-context_$activeId'),
                      sessionId: activeId,
                    ),
                  ),
                ),
          body: Stack(
            children: [
              const SessionNotificationWatcher(),
              const UpdatesPeriodicWatcher(),
              const StartupUpdatesWatcher(),
              SafeArea(
                // Rounded-corner phones: the web view reports no safe area, so leave the same margin
                // below as at the sides; the panel's corners then follow the display curve.
                minimum: EdgeInsets.only(
                  bottom: phoneDisplayCornerRadius(context) == null ? 0 : 6,
                ),
                child: Column(
                  children: [
                    FocusRegionMarker(
                      region: FocusRegion.titleBar,
                      regionKey: _regionKeys[FocusRegion.titleBar]!,
                      child: Container(
                        height: 42,
                        margin: EdgeInsets.fromLTRB(
                          width < 600 ? 12 : 8,
                          width < 600 ? 6 : 4,
                          width < 600 ? 12 : 8,
                          4,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.chassis,
                          borderRadius: BorderRadius.circular(tokens.radiusMd),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Row(
                          children: [
                            if (!kIsWeb &&
                                defaultTargetPlatform == TargetPlatform.macOS &&
                                nativeChrome)
                              const SizedBox(width: 76),
                            if (!showSessionRail)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: strings.openSessionsTooltip,
                                icon: const Icon(
                                  Icons.menu_outlined,
                                  size: FrameSize.icon,
                                ),
                                onPressed: () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                              ),
                            Expanded(
                              child: DesktopDragRegion(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: showSessionRail ? 16 : 4,
                                  ),
                                  child: Row(
                                    children: [
                                      const PiFrameMark(size: FrameSize.iconLg),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: const BrandWordmark(
                                            size: FrameSize.icon,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _ConnectionIndicator(
                                        connected: connected,
                                        label: connectionLabel,
                                        tooltip: strings
                                            .connectionIndicatorTooltip(
                                              connectionLabel,
                                            ),
                                        showLabel:
                                            width >= kConnectionLabelMinWidth,
                                        onTap: _openDiagnostics,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (ref.watch(nerdStatsSettingsProvider).enabled &&
                                width >=
                                    (ref.watch(isWebProvider) ? 450 : 760)) ...[
                              const SizedBox(width: 8),
                              NerdStatsBar(width: width),
                              const SizedBox(width: 8),
                            ],
                            if (width > 680)
                              PressFeedback(
                                child: TextButton.icon(
                                  onPressed: _palette,
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    foregroundColor: tokens.textSecondary,
                                  ),
                                  icon: const Icon(
                                    Icons.search_outlined,
                                    size: FrameSize.icon,
                                  ),
                                  label: Text(
                                    strings.commandsButtonLabel,
                                    style: FrameText.of(context).label,
                                  ),
                                ),
                              ),
                            // Vista: pane layout and theme.
                            Semantics(
                              container: true,
                              label: strings.viewGroupLabel,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (width >= 900 &&
                                      activeId != null &&
                                      !settings)
                                    PopupMenuButton<WorkspacePane>(
                                      key: const ValueKey(
                                        'shell-layout-button',
                                      ),
                                      tooltip: strings.togglePanelsTooltip,
                                      icon: const Icon(
                                        Icons.view_column_outlined,
                                        size: FrameSize.icon,
                                      ),
                                      padding: EdgeInsets.zero,
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
                                                      : Icons
                                                            .check_box_outline_blank,
                                                  size: FrameSize.iconLg,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(_paneLabel(pane)),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  FrameIconAction(
                                    key: const ValueKey('shell-theme-toggle'),
                                    tooltip:
                                        Theme.of(context).brightness ==
                                            Brightness.light
                                        ? strings.darkThemeTooltip
                                        : strings.lightThemeTooltip,
                                    icon:
                                        Theme.of(context).brightness ==
                                            Brightness.light
                                        ? Icons.dark_mode_outlined
                                        : Icons.light_mode_outlined,
                                    onPressed: () => ref
                                        .read(activeThemeSpecProvider.notifier)
                                        .setTheme(
                                          Theme.of(context).brightness ==
                                                  Brightness.light
                                              ? 'piframe-dark'
                                              : 'piframe-light',
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              key: const ValueKey('shell-title-divider'),
                              width: 1,
                              height: 18,
                              margin: const EdgeInsets.symmetric(
                                horizontal: FrameSpace.x2,
                              ),
                              color: tokens.borderStrong,
                            ),
                            // Area di lavoro: session drawer and settings.
                            Semantics(
                              container: true,
                              label: strings.workspaceTitle,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (activeId != null && !settings)
                                    width >= kContextDrawerLabelMinWidth
                                        ? Tooltip(
                                            message:
                                                strings.sessionDrawerTooltip,
                                            child: TextButton.icon(
                                              key: const ValueKey(
                                                'shell-context-drawer-button',
                                              ),
                                              style: TextButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: FrameSpace.x2,
                                                      vertical: FrameSpace.x1,
                                                    ),
                                                foregroundColor:
                                                    tokens.textSecondary,
                                              ),
                                              onPressed: () => _scaffoldKey
                                                  .currentState
                                                  ?.openEndDrawer(),
                                              icon: const Icon(
                                                Icons.insights_outlined,
                                                size: FrameSize.icon,
                                              ),
                                              label: Text(
                                                strings.sessionDrawerLabel,
                                                style: FrameText.of(context)
                                                    .label,
                                              ),
                                            ),
                                          )
                                        : FrameIconAction(
                                            key: const ValueKey(
                                              'shell-context-drawer-button',
                                            ),
                                            icon: Icons.insights_outlined,
                                            tooltip:
                                                strings.sessionDrawerTooltip,
                                            onPressed: () => _scaffoldKey
                                                .currentState
                                                ?.openEndDrawer(),
                                          ),
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      FrameIconAction(
                                        key: const ValueKey(
                                          'shell-settings-button',
                                        ),
                                        icon: Icons.settings_outlined,
                                        tooltip: strings.settingsTooltip,
                                        shortcut: strings.settingsShortcutLabel,
                                        onPressed: () =>
                                            ref
                                                    .read(
                                                      showSettingsProvider
                                                          .notifier,
                                                    )
                                                    .state =
                                                !settings,
                                      ),
                                      Positioned(
                                        top: 2,
                                        right: 2,
                                        child: IgnorePointer(
                                          child: Consumer(
                                            builder: (context, ref, _) {
                                              if (!ref.watch(
                                                hasUpdateBadgeProvider,
                                              )) {
                                                return const SizedBox.shrink();
                                              }
                                              return Container(
                                                width: 7,
                                                height: 7,
                                                decoration: BoxDecoration(
                                                  color: tokens.accent,
                                                  shape: BoxShape.circle,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (nativeChrome &&
                                defaultTargetPlatform ==
                                    TargetPlatform.windows) ...[
                              Container(
                                width: 1,
                                height: 18,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                color: tokens.borderStrong,
                              ),
                              DesktopCaptionButtons(
                                onCloseRequested: () => resolveDirtyRepository(
                                  context,
                                  ref,
                                  activeId,
                                ),
                              ),
                            ] else
                              const SizedBox(width: 6),
                          ],
                        ),
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
                            Icon(
                              Icons.link_off_outlined,
                              size: FrameSize.icon,
                              color: tokens.warning,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                connection == DaemonConnectionState.reconnecting
                                    ? strings.reconnectingToDaemon
                                    : strings.daemonUnreachableNotice,
                                style: FrameText.of(context).label
                                    .copyWith(color: tokens.textPrimary),
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: tokens.textPrimary,
                              ),
                              onPressed: () =>
                                  ref.invalidate(daemonEndpointProvider),
                              child: Text(strings.retryAction),
                            ),
                          ],
                        ),
                      ),
                    // Full-width notice under the title bar when the sessions
                    // rail is not showing; the rail hosts it otherwise.
                    if (!bannerInRail) const StartupUpdateBanner(),
                    Expanded(
                      child: settings
                          ? SettingsView(
                              key: ValueKey('settings-view-$_settingsEpoch'),
                              initialTabIndex: ref.watch(
                                settingsTabIndexProvider,
                              ),
                              initialSection: _settingsSection,
                              onClose: () =>
                                  ref
                                          .read(showSettingsProvider.notifier)
                                          .state =
                                      false,
                            )
                          : Row(
                              children: [
                                if (showSessionRail)
                                  FocusRegionMarker(
                                    region: FocusRegion.sessions,
                                    regionKey:
                                        _regionKeys[FocusRegion.sessions]!,
                                    child: _sidebarCollapsed
                                        ? _collapsedSidebarStrip(tokens)
                                        : _sessionsSidebar(width),
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
      ),
    );
  }

  Widget _workspace(String sessionId, double width, Widget Function() chat) {
    _chatSidecarSessionId = sessionId;
    _chatSidecar = AgentActivitySidecar(
      key: ValueKey('agent_activity_$sessionId'),
      sessionId: sessionId,
      onOpened: () {
        if (mounted &&
            _paneVisibility[WorkspacePane.git] == true &&
            !_collapsedPanes.contains(WorkspacePane.git) &&
            !ref.read(isReviewingChangesProvider)) {
          _collapsePane(WorkspacePane.git);
        }
        // Half-width windows: if the panel still has to float over the chat,
        // fold the Repository pane to its strip once so the panel can dock
        // beside the chat. Only on opening, so expanding it again sticks.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              agentSidecarFloating[sessionId] == true &&
              _paneVisibility[WorkspacePane.repository] == true &&
              !_collapsedPanes.contains(WorkspacePane.repository) &&
              !ref.read(isReviewingChangesProvider)) {
            _collapsePane(WorkspacePane.repository);
          }
        });
      },
    );
    final isReviewing = ref.watch(isReviewingChangesProvider);
    final visible = _visiblePanes(chatFirst: width < 900);
    final companions = visible
        .where((pane) => pane != WorkspacePane.chat)
        .toList();
    final companionTabs = width >= 900 && width < 1440 && companions.length > 1
        ? companions
        : null;
    final selectedCompanion = companions.contains(_companionPane)
        ? _companionPane
        : (companions.isNotEmpty ? companions.first : null);

    final panes = <WorkspacePane, Widget>{
      WorkspacePane.repository: RepositoryPane(
        key: ValueKey('repo_$sessionId'),
        sessionId: sessionId,
        onCollapse: () => _collapsePane(WorkspacePane.repository),
        companionTabs: companionTabs,
        activeCompanionTab: selectedCompanion,
        onSelectCompanionTab: (pane) => _selectCompanionPane(pane),
      ),
      WorkspacePane.chat: chat(),
      WorkspacePane.git: isReviewing
          ? SessionChangesPane(
              key: ValueKey('review_changes_$sessionId'),
              sessionId: sessionId,
              onClose: () =>
                  ref.read(isReviewingChangesProvider.notifier).state = false,
              companionTabs: companionTabs,
              activeCompanionTab: selectedCompanion,
              onSelectCompanionTab: (pane) => _selectCompanionPane(pane),
            )
          : (ref.watch(browserPaneSupportedProvider) &&
                    ref.watch(rightPaneModeProvider) == RightPaneMode.browser
                ? WebBrowserPane(
                    key: ValueKey('browser_$sessionId'),
                    sessionId: sessionId,
                    onCollapse: () => _collapsePane(WorkspacePane.git),
                    companionTabs: companionTabs,
                    activeCompanionTab: selectedCompanion,
                    onSelectCompanionTab: (pane) => _selectCompanionPane(pane),
                  )
                : GitChangesPane(
                    key: ValueKey('git_$sessionId'),
                    sessionId: sessionId,
                    onCollapse: () => _collapsePane(WorkspacePane.git),
                    companionTabs: companionTabs,
                    activeCompanionTab: selectedCompanion,
                    onSelectCompanionTab: (pane) => _selectCompanionPane(pane),
                  )),
    };
    // Tab order by region (plan task 6.2). The chat pane's transcript and composer are
    // marked inside workArea().
    panes[WorkspacePane.repository] = _regionMarker(
      FocusRegion.repository,
      panes[WorkspacePane.repository]!,
    );
    panes[WorkspacePane.git] = _regionMarker(
      FocusRegion.companion,
      panes[WorkspacePane.git]!,
    );

    if (width < 900) {
      final selected = visible.contains(_compactPane)
          ? _compactPane
          : visible.first;
      return Column(
        children: [
          _paneSelector(
            visible,
            selected,
            (pane) => _selectCompactPane(pane),
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
      if (companions.isNotEmpty && selectedCompanion != null) {
        return _resizablePaneRow([
          WorkspacePane.chat,
          selectedCompanion,
        ], panes);
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

  String _paneLabel(WorkspacePane pane) {
    final strings = ref.watch(appStringsProvider);
    return switch (pane) {
      WorkspacePane.chat => strings.companionChatTab,
      WorkspacePane.repository => strings.paletteRepositoryPaneName,
      WorkspacePane.git =>
        ref.watch(isReviewingChangesProvider)
            ? strings.companionReviewTab
            : (ref.watch(browserPaneSupportedProvider) &&
                      ref.watch(rightPaneModeProvider) == RightPaneMode.browser
                  ? strings.companionWebBrowserTab
                  : strings.paletteGitPaneName),
    };
  }

  bool get _reducedMotion => FrameMotion.reduced(context);

  /// Starts a pane width transition from the layout on screen. Call it before
  /// the state change: the next build interpolates from [_slotPx] to the new
  /// layout over the `panel` (show) or `panelExit` (hide) token.
  void _beginPaneTransition({required bool animate, required bool showing}) {
    if (!animate) {
      _paneTransition.stop();
      _paneAnimating = false;
      _exitingPanes.clear();
      return;
    }
    _slotFromPx = Map.of(_slotPx);
    _paneAnimating = true;
    // Reduced motion: the layout is final at once and the entering pane
    // cross-fades over the crossFade token (120 ms, within the 150 ms limit).
    _paneTransition.duration = _reducedMotion
        ? FrameMotion.crossFade
        : (showing ? FrameMotion.panel : FrameMotion.panelExit);
    _paneTransition.forward(from: 0);
  }

  void _onPaneTransitionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _paneAnimating = false;
      _exitingPanes.clear();
    });
  }

  void _togglePane(WorkspacePane pane, {bool animate = true}) {
    final visible = _visiblePanes();
    if (_paneVisibility[pane] == true && visible.length <= 1) return;
    final nowVisible = !(_paneVisibility[pane] ?? false);
    _beginPaneTransition(animate: animate, showing: nowVisible);
    final rowIndex = _rowOrder.indexOf(pane);
    if (animate && !nowVisible && rowIndex >= 0 && !_reducedMotion) {
      _exitingPanes[pane] = rowIndex;
    }
    setState(() {
      _paneVisibility[pane] = nowVisible;
      if (nowVisible) {
        _collapsedPanes.remove(pane);
        _exitingPanes.remove(pane);
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
    _persistLayout();
  }

  /// Marks [child] as [region] for Tab order and F6 (see [FocusRegionMarker]).
  Widget _regionMarker(FocusRegion region, Widget child) => FocusRegionMarker(
    region: region,
    regionKey: _regionKeys[region]!,
    child: child,
  );

  /// Chat keeps the Agents/Workflows column as a sibling card on its right.
  Widget _paneCard(WorkspacePane pane, Widget child) {
    final sidecar = _chatSidecar;
    final sessionId = _chatSidecarSessionId;
    if (pane != WorkspacePane.chat || sidecar == null || sessionId == null) {
      return _bentoPane(child);
    }
    return AgentSidecarLayout(
      sessionId: sessionId,
      chat: _bentoPane(child),
      // The sidecar belongs to the chat pane for Tab order, after the transcript.
      sidecar: FocusTraversalOrder(
        order: NumericFocusOrder(FocusRegion.transcript.index.toDouble()),
        child: sidecar,
      ),
    );
  }

  Widget _bentoPane(Widget child) {
    final tokens = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;
    final baseRadius = isMobile ? tokens.radiusMd : tokens.radiusLg;
    // iOS concentric corners: the bottom corners follow the display curve (display radius minus
    // the 8px the panel is inset from the screen edge).
    final displayRadius = phoneDisplayCornerRadius(context);
    final bottomRadius = displayRadius == null
        ? baseRadius
        : concentricRadius(displayRadius, 8, min: baseRadius);
    // Inset between the frame edge and its content (matches the padding below).
    final paneInset = isMobile ? 2.0 : 3.0;
    return RepaintBoundary(
      child: Padding(
        padding: isMobile
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
            : EdgeInsets.all(paneInset),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(baseRadius),
              topRight: Radius.circular(baseRadius),
              bottomLeft: Radius.circular(bottomRadius),
              bottomRight: Radius.circular(bottomRadius),
            ),
          ),
          // Concentric: content clips at the outer radius minus the inset, so
          // headers and fills follow the frame corner without a gap.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              math.max(0, baseRadius - paneInset),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  void _collapsePane(WorkspacePane pane, {bool animate = true}) {
    final visible = _visiblePanes();
    final openPanes = visible
        .where((p) => !_collapsedPanes.contains(p))
        .toList();
    if (openPanes.length <= 1) return; // Always keep at least one pane open

    _beginPaneTransition(animate: animate, showing: false);
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
    _persistLayout();
  }

  /// Expands a pane from its strip. A companion the layout collapsed only for being
  /// narrower than kCompanionMinWidth is not in _collapsedPanes, so it is added first.
  void _expandStripPane(WorkspacePane pane) {
    _collapsedPanes.add(pane);
    _expandPane(pane);
  }

  void _expandPane(WorkspacePane pane, {bool animate = true}) {
    if (!_collapsedPanes.contains(pane)) return;
    _beginPaneTransition(animate: animate, showing: true);
    setState(() {
      _collapsedPanes.remove(pane);
      final visible = _visiblePanes();
      final openOthers = visible
          .where((p) => p != pane && !_collapsedPanes.contains(p))
          .toList();

      var restoreWeight = (_savedPaneWeights[pane] ?? 30).clamp(15.0, 50.0);
      // Restoring must not hand the pane a share narrower than the companion
      // minimum, or the layout would collapse it again straight away.
      if (_rowWidth > 0) {
        final minWeight = (kCompanionMinWidth * 100 / _rowWidth * 1.05)
            .clamp(15.0, 60.0)
            .toDouble();
        if (restoreWeight < minWeight) restoreWeight = minWeight;
      }
      _paneWeights[pane] = restoreWeight;

      if (openOthers.isNotEmpty) {
        final totalOther = openOthers.fold<double>(
          0.0,
          (sum, p) => sum + (_paneWeights[p] ?? 30),
        );
        final targetOther = (100.0 - restoreWeight).clamp(20.0, 85.0);
        final factor = totalOther > 0 ? targetOther / totalOther : 1.0;
        for (final other in openOthers) {
          _paneWeights[other] = ((_paneWeights[other] ?? 30) * factor).clamp(
            10.0,
            85.0,
          );
        }
      }
    });
    _persistLayout();
  }

  Widget _collapsedPaneStrip(WorkspacePane pane) {
    final tokens = context.tokens;
    final isLeft = pane == WorkspacePane.repository;
    final isBrowser =
        pane == WorkspacePane.git &&
        !ref.watch(isReviewingChangesProvider) &&
        ref.watch(browserPaneSupportedProvider) &&
        ref.watch(rightPaneModeProvider) == RightPaneMode.browser;
    final iconData = switch (pane) {
      WorkspacePane.repository => Icons.folder_outlined,
      WorkspacePane.git =>
        isBrowser ? Icons.language_outlined : Icons.source_outlined,
      WorkspacePane.chat => Icons.chat_bubble_outline,
    };
    final expandIcon = isLeft
        ? Icons.chevron_right_outlined
        : Icons.chevron_left_outlined;
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
                tooltip: strings.expandPaneTooltip(_paneLabel(pane)),
                icon: Icon(
                  expandIcon,
                  size: FrameSize.iconLg,
                  color: tokens.accent,
                ),
                onPressed: () => _expandStripPane(pane),
              ),
              const SizedBox(height: 6),
              Icon(iconData, size: FrameSize.icon, color: tokens.textMuted),
              const SizedBox(height: 12),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Center(
                    child: Text(
                      label,
                      style: FrameText.of(context).caption.copyWith(
                        color: tokens.textMuted,

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

  double _effectiveSidebarWidth(double windowWidth, {bool inDrawer = false}) {
    return _clampSidebarWidth(_sidebarWidth, windowWidth, inDrawer: inDrawer);
  }

  double _clampSidebarWidth(
    double value,
    double windowWidth, {
    bool inDrawer = false,
  }) {
    final maximum = inDrawer
        ? (windowWidth - 32).clamp(0.0, _maximumSidebarWidth).toDouble()
        : _maximumSidebarWidth;
    final minimum = maximum < _minimumSidebarWidth
        ? maximum
        : _minimumSidebarWidth;
    return value.clamp(minimum, maximum).toDouble();
  }

  void _resizeSidebar(
    double delta,
    double windowWidth, {
    required bool inDrawer,
  }) {
    final current = _effectiveSidebarWidth(windowWidth, inDrawer: inDrawer);
    setState(() {
      _sidebarWidth = _clampSidebarWidth(
        current + delta,
        windowWidth,
        inDrawer: inDrawer,
      );
    });
  }

  void _finishSidebarResize() {
    ref.read(paneDraggingProvider.notifier).state = false;
    _persistLayout();
  }

  /// Keyboard step on the sessions divider (plan task 6.7). Same resize path as a drag.
  void _stepSidebar(
    double delta,
    double windowWidth, {
    required bool inDrawer,
  }) {
    _resizeSidebar(delta, windowWidth, inDrawer: inDrawer);
    _persistLayout();
  }

  /// The 1 px line drawn inside every divider. It turns accent-coloured while focused.
  Widget _dividerLine(BuildContext context, bool focused) {
    final tokens = context.tokens;
    return Container(
      width: focused ? 2 : 1,
      height: 40,
      color: focused ? tokens.accent : tokens.borderStrong,
    );
  }

  Widget _sessionsSidebar(double windowWidth, {bool inDrawer = false}) {
    final sidebarWidth = _effectiveSidebarWidth(
      windowWidth,
      inDrawer: inDrawer,
    );
    final increasedWidth = _clampSidebarWidth(
      sidebarWidth + 20,
      windowWidth,
      inDrawer: inDrawer,
    );
    final decreasedWidth = _clampSidebarWidth(
      sidebarWidth - 20,
      windowWidth,
      inDrawer: inDrawer,
    );
    final sidebar = SizedBox(
      key: const ValueKey('sessions-sidebar-pane'),
      width: sidebarWidth,
      child: Column(
        children: [
          if (!inDrawer) const StartupUpdateBanner(inRail: true),
          Expanded(
            child: SessionsSidebar(
              onSessionSelected: inDrawer
                  ? () => _scaffoldKey.currentState?.closeDrawer()
                  : null,
              onCollapse: inDrawer
                  ? null
                  : () {
                      setState(() => _sidebarCollapsed = true);
                      _persistLayout();
                    },
            ),
          ),
        ],
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        inDrawer ? sidebar : _bentoPane(sidebar),
        MouseRegion(
          key: const ValueKey('sessions-sidebar-divider'),
          cursor: SystemMouseCursors.resizeLeftRight,
          child: _ResizeDividerFocus(
            label: strings.sessionsSidebarDividerLabel,
            value: strings.dividerPixelValue(sidebarWidth.round()),
            increasedValue: strings.dividerPixelValue(increasedWidth.round()),
            decreasedValue: strings.dividerPixelValue(decreasedWidth.round()),
            onIncrease: increasedWidth > sidebarWidth
                ? () => _stepSidebar(20, windowWidth, inDrawer: inDrawer)
                : null,
            onDecrease: decreasedWidth < sidebarWidth
                ? () => _stepSidebar(-20, windowWidth, inDrawer: inDrawer)
                : null,
            builder: (context, focused) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) =>
                  ref.read(paneDraggingProvider.notifier).state = true,
              onHorizontalDragUpdate: (details) => _resizeSidebar(
                details.delta.dx,
                windowWidth,
                inDrawer: inDrawer,
              ),
              onHorizontalDragEnd: (_) => _finishSidebarResize(),
              onHorizontalDragCancel: _finishSidebarResize,
              child: Tooltip(
                message: strings.sessionsSidebarDividerTooltip,
                child: SizedBox(
                  width: _sidebarDividerWidth,
                  child: Center(child: _dividerLine(context, focused)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _collapsedSidebarStrip(FrameTokens tokens) {
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
                tooltip: strings.expandSessionsSidebarTooltip,
                icon: Icon(
                  Icons.chevron_right_outlined,
                  size: FrameSize.iconLg,
                  color: tokens.accent,
                ),
                onPressed: () {
                  setState(() => _sidebarCollapsed = false);
                  _persistLayout();
                },
              ),
              const SizedBox(height: 8),
              const PiFrameMark(size: FrameSize.iconLg),
              const SizedBox(height: 12),
              Icon(
                Icons.chat_bubble_outline,
                size: FrameSize.icon,
                color: tokens.textMuted,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Center(
                    child: Text(
                      strings.sessionsRailHeader,
                      style: FrameText.of(context).caption.copyWith(
                        color: tokens.textMuted,

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
    if (panes.length == 1 && _collapsedPanes.isEmpty && _exitingPanes.isEmpty) {
      return _paneCard(panes.single, contents[panes.single]!);
    }
    final rowPanes = _withExitingPanes(panes);
    // Every slot is a fixed width in pixels. The row is rebuilt on each frame of
    // a pane transition, so widths interpolate from the last layout on screen.
    return AnimatedBuilder(
      animation: _paneTransition,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          const dividerWidth = 8.0;
          const collapsedWidth = 40.0;
          _rowWidth = constraints.maxWidth;
          final openWidth =
              constraints.maxWidth - dividerWidth * (rowPanes.length - 1);
          final stateCollapsed = panes
              .where((p) => _collapsedPanes.contains(p))
              .length;
          if (_pendingWeightClamp && openWidth > 0) {
            _pendingWeightClamp = false;
            _paneWeights.addAll(
              clampRestoredPaneWeights(
                panes: panes,
                collapsed: _collapsedPanes,
                weights: _paneWeights,
                availableWidth: openWidth - collapsedWidth * stateCollapsed,
              ),
            );
          }
          // A companion narrower than kCompanionMinWidth collapses to its tab.
          final narrow = narrowCompanionPanes(
            panes: panes,
            collapsed: _collapsedPanes,
            weights: {
              for (final p in panes)
                p: (_paneWeights[p] ?? 1).round().clamp(1, 100).toInt(),
            },
            availableWidth: openWidth - collapsedWidth * stateCollapsed,
          );
          bool isCollapsed(WorkspacePane p) =>
              _collapsedPanes.contains(p) || narrow.contains(p);
          final collapsedCount = panes.where(isCollapsed).length;
          final availableWidth = openWidth - (collapsedWidth * collapsedCount);
          int flexOf(WorkspacePane p) =>
              (_paneWeights[p] ?? 1).round().clamp(1, 100).toInt();
          final openFlex = panes
              .where((p) => !isCollapsed(p))
              .fold<int>(0, (sum, p) => sum + flexOf(p));
          final targets = <WorkspacePane, double>{
            for (final p in rowPanes)
              p: !panes.contains(p)
                  ? 0.0
                  : isCollapsed(p)
                  ? collapsedWidth
                  : (openFlex > 0
                        ? availableWidth * flexOf(p) / openFlex
                        : 0.0),
          };
          final shown = _displayedWidths(rowPanes, targets, openWidth);
          _slotPx = shown;
          _rowOrder = rowPanes;

          final children = <Widget>[];
          for (var index = 0; index < rowPanes.length; index++) {
            final pane = rowPanes[index];
            final Widget body;
            if (!panes.contains(pane)) {
              body = const SizedBox.shrink(); // hidden, still shrinking
            } else if (isCollapsed(pane)) {
              body = _collapsedPaneStrip(pane);
            } else {
              final fromPx = _slotFromPx[pane] ?? 0;
              final isEntering = fromPx <= 40;
              final card = _paneCard(pane, contents[pane]!);
              body = Opacity(
                opacity: _entryAlpha(pane, targets[pane]!),
                child: isEntering
                    ? FrameEnter(key: ValueKey('pane-enter-$pane'), child: card)
                    : card,
              );
            }
            children.add(
              _paneSlot(
                width: shown[pane]!,
                layoutWidth: targets[pane]!,
                child: body,
              ),
            );
            if (index < rowPanes.length - 1) {
              children.add(
                _paneDivider(pane, rowPanes[index + 1], availableWidth),
              );
            }
          }
          return Row(children: children);
        },
      ),
    );
  }

  /// The visible panes plus any hidden pane still shrinking, at its old index.
  List<WorkspacePane> _withExitingPanes(List<WorkspacePane> panes) {
    final rows = List<WorkspacePane>.of(panes);
    final exiting = _exitingPanes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final entry in exiting) {
      if (rows.contains(entry.key)) continue;
      rows.insert(
        entry.value > rows.length ? rows.length : entry.value,
        entry.key,
      );
    }
    return rows;
  }

  /// Slot widths in pixels for this frame. Animating, each slot moves from its
  /// width in the layout on screen to its target. The starting widths are
  /// scaled to the row, so the total never changes during the transition.
  Map<WorkspacePane, double> _displayedWidths(
    List<WorkspacePane> rowPanes,
    Map<WorkspacePane, double> targets,
    double rowWidth,
  ) {
    final raw = <WorkspacePane, double>{};
    if (!_paneAnimating || _reducedMotion) {
      raw.addAll(targets);
    } else {
      final eased = FrameMotion.panelCurve.transform(_paneTransition.value);
      var fromTotal = 0.0;
      for (final p in rowPanes) {
        fromTotal += _slotFromPx[p] ?? 0;
      }
      final scale = fromTotal > 0 ? rowWidth / fromTotal : 1.0;
      for (final p in rowPanes) {
        final from = (_slotFromPx[p] ?? 0) * scale;
        raw[p] = from + (targets[p]! - from) * eased;
      }
    }
    return _snapToRow(raw, rowPanes, rowWidth);
  }

  /// Rounds slot widths down to a thousandth of a pixel and keeps a margin
  /// under [rowWidth], so the row never overflows on floating-point rounding.
  Map<WorkspacePane, double> _snapToRow(
    Map<WorkspacePane, double> raw,
    List<WorkspacePane> rowPanes,
    double rowWidth,
  ) {
    final out = <WorkspacePane, double>{};
    for (final p in rowPanes) {
      final v = raw[p] ?? 0;
      out[p] = (v > 0 ? (v * 1000).floorToDouble() / 1000 : 0.0);
    }
    final total = out.values.fold<double>(0, (sum, v) => sum + v);
    final excess = total - (rowWidth - 0.001);
    if (excess > 0 && out.isNotEmpty) {
      final largest = out.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      final reduced = out[largest]! - excess;
      out[largest] = reduced > 0 ? reduced : 0.0;
    }
    return out;
  }

  /// Opacity of an entering pane's content. Under motion it appears after 60 %
  /// of the travel. Under reduced motion it cross-fades over the whole duration
  /// at the final layout. Panes that are not entering stay opaque.
  double _entryAlpha(WorkspacePane pane, double target) {
    if (!_paneAnimating) return 1;
    final from = _slotFromPx[pane] ?? 0;
    // An existing open pane expanding width must stay fully opaque at all times:
    if (from > 40 && !_collapsedPanes.contains(pane)) return 1;
    if (from >= target - 0.5) return 1;
    final t = _paneTransition.value;
    if (_reducedMotion) return t;
    return ((t - 0.6) / 0.4).clamp(0.0, 1.0);
  }

  /// One pane slot. [width] is the animated slot width, and [layoutWidth] the
  /// final width the child is laid out at, so its content does not reflow while
  /// the slot clips it.
  Widget _paneSlot({
    required double width,
    required double layoutWidth,
    required Widget child,
  }) {
    return SizedBox(
      width: width,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: layoutWidth,
          maxWidth: layoutWidth,
          child: RepaintBoundary(
            child: SizedBox(width: layoutWidth, child: child),
          ),
        ),
      ),
    );
  }

  Widget _paneDivider(
    WorkspacePane left,
    WorkspacePane right,
    double availableWidth,
  ) {
    const dividerWidth = 8.0;
    return FocusTraversalOrder(
      order: NumericFocusOrder(_dividerFocusOrder(left)),
      child: MouseRegion(
        key: ValueKey('pane-divider-$left-$right'),
        cursor: SystemMouseCursors.resizeLeftRight,
        child: _ResizeDividerFocus(
          label: strings.paneDividerLabel(_paneLabel(left), _paneLabel(right)),
          value: strings.dividerPercentValue(_leftSharePercent(left, right)),
          onIncrease: () => _stepAdjacent(left, right, 20, availableWidth),
          onDecrease: () => _stepAdjacent(left, right, -20, availableWidth),
          builder: (context, focused) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) =>
                ref.read(paneDraggingProvider.notifier).state = true,
            onHorizontalDragEnd: (_) {
              ref.read(paneDraggingProvider.notifier).state = false;
              _persistLayout();
            },
            onHorizontalDragCancel: () {
              ref.read(paneDraggingProvider.notifier).state = false;
              _persistLayout();
            },
            onHorizontalDragUpdate: (details) =>
                _resizeAdjacent(left, right, details.delta.dx, availableWidth),
            child: SizedBox(
              width: dividerWidth,
              child: Center(child: _dividerLine(context, focused)),
            ),
          ),
        ),
      ),
    );
  }

  /// Tab order of the divider after the pane [left] (plan task 6.2): it follows the
  /// region that ends at the divider, so it sits between two panes, not after all of them.
  double _dividerFocusOrder(WorkspacePane left) => switch (left) {
    WorkspacePane.repository => FocusRegion.repository.index + 0.5,
    WorkspacePane.chat => FocusRegion.composer.index + 0.5,
    WorkspacePane.git => FocusRegion.companion.index + 0.5,
  };

  /// Keyboard step on a pane divider (plan task 6.7). Same path as a drag, then saved.
  void _stepAdjacent(
    WorkspacePane left,
    WorkspacePane right,
    double delta,
    double availableWidth,
  ) {
    _resizeAdjacent(left, right, delta, availableWidth);
    _persistLayout();
  }

  /// Share of the two neighbouring panes that the left one occupies, for screen readers.
  int _leftSharePercent(WorkspacePane left, WorkspacePane right) {
    final leftWeight = _paneWeights[left] ?? 1;
    final total = leftWeight + (_paneWeights[right] ?? 1);
    if (total <= 0) return 50;
    return (leftWeight / total * 100).round();
  }

  void _resizeAdjacent(
    WorkspacePane left,
    WorkspacePane right,
    double delta,
    double availableWidth,
  ) {
    // Divider drags and keyboard steps are instant: no pane width transition.
    if (_collapsedPanes.contains(left)) {
      if (delta > 6) {
        _expandPane(left, animate: false);
      }
      return;
    }
    if (_collapsedPanes.contains(right)) {
      if (delta < -6) {
        _expandPane(right, animate: false);
      }
      return;
    }

    final leftWeight = _paneWeights[left] ?? 1;
    final rightWeight = _paneWeights[right] ?? 1;
    final total = leftWeight + rightWeight;
    if (availableWidth <= 0 || total <= 0) return;

    final minimum = total * 0.15;
    final candidateLeft = leftWeight + delta / availableWidth * total;

    final openCount = _visiblePanes()
        .where((p) => !_collapsedPanes.contains(p))
        .length;
    if (openCount > 1) {
      if (candidateLeft < minimum) {
        _collapsePane(left, animate: false);
        return;
      }
      if (total - candidateLeft < minimum) {
        _collapsePane(right, animate: false);
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
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;
    final isBrowser =
        ref.watch(browserPaneSupportedProvider) &&
        ref.watch(rightPaneModeProvider) == RightPaneMode.browser;
    final strings = ref.watch(appStringsProvider);
    // The run status rides on the Chat tab as a dot (task 10.3).
    final activeId = ref.watch(activeSessionIdProvider);
    final running =
        activeId != null && ref.watch(sessionStateFamily(activeId)).isStreaming;
    String label(WorkspacePane pane) => switch (pane) {
      WorkspacePane.chat => strings.companionChatTab,
      WorkspacePane.repository => strings.companionFileTab,
      WorkspacePane.git =>
        isBrowser ? strings.companionWebBrowserTab : strings.paletteGitPaneName,
    };
    return Container(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 6, vertical: 2),
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
                  label: pane == WorkspacePane.chat && running
                      ? '${label(pane)}, ${strings.companionChatRunningLabel}'
                      : null,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      foregroundColor: pane == selected
                          ? tokens.accent
                          : tokens.textPrimary,
                      backgroundColor: tokens.chassis,
                      shape: const RoundedRectangleBorder(),
                    ),
                    onPressed: () => onSelected(pane),
                    child: Container(
                      // Selected tab: accent text and a 2 px accent underline.
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: pane == selected
                                ? tokens.accent
                                : tokens.chassis,
                            width: 2,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              label(pane),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (pane == WorkspacePane.chat && running) ...[
                            const SizedBox(width: 6),
                            Container(
                              key: const ValueKey('compact-chat-run-dot'),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: tokens.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (showLayoutMenu)
            PopupMenuButton<WorkspacePane>(
              tooltip: strings.togglePanelsTooltip,
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
                          size: FrameSize.iconLg,
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
}
