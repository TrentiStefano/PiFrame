import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_shell.dart';
import '../../data/terminal/terminal_settings.dart';
import '../../data/theme/theme_providers.dart';
import '../../ui/frame_focus.dart';
import '../../ui/frame_snack_bar.dart';
import '../session_changes/session_changes_provider.dart';
import '../sessions_sidebar/session_actions.dart';
import '../browser/browser_models.dart';
import '../browser/browser_controller.dart';
import '../side/side_provider.dart';
import '../workspace/repository_workspace.dart';

// Layout constants with no matching token in FrameSpace / FrameSize.
const _rowHeight = 52.0;
const _rowIconSize = 18.0;
const _rowIconGap = 14.0;
const _emptyStatePadding = 20.0;
const _groupHeaderHeight = FrameSize.rowList;
const _dialogMaxWidth = 540.0;

class PaletteAction {
  final String id;
  final String group;
  final String title;
  final String subtitle;
  final IconData icon;

  /// Key caps shown right-aligned. Only real, bound shortcuts belong here.
  final List<String> keys;

  /// Switches the palette to the session list instead of running a command.
  final bool opensSessionPicker;
  final Future<void> Function() onExecute;

  const PaletteAction({
    required this.id,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onExecute,
    this.keys = const [],
    this.opensSessionPicker = false,
  });
}

class CommandPalette extends ConsumerStatefulWidget {
  final BuildContext hostContext;
  final WidgetRef hostRef;
  final VoidCallback? onOpenSettings;
  final bool Function(WorkspacePane pane)? isPaneVisible;
  final void Function(WorkspacePane pane)? onTogglePane;

  const CommandPalette({
    super.key,
    required this.hostContext,
    required this.hostRef,
    this.onOpenSettings,
    this.isPaneVisible,
    this.onTogglePane,
  });

  /// [ref] belongs to the caller. Commands run after the palette closes, so they
  /// must not depend on this palette's own (soon disposed) ref.
  static Future<void> show(
    BuildContext context, {
    required WidgetRef ref,
    VoidCallback? onOpenSettings,
    bool Function(WorkspacePane pane)? isPaneVisible,
    void Function(WorkspacePane pane)? onTogglePane,
  }) {
    return showDialog(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      barrierColor: context.tokens.overlay,
      builder: (_) => CommandPalette(
        hostContext: context,
        hostRef: ref,
        onOpenSettings: onOpenSettings,
        isPaneVisible: isPaneVisible,
        onTogglePane: onTogglePane,
      ),
    );
  }

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  int _selectedIndex = 0;
  bool _sessionMode = false;
  bool _executing = false;

  // Laid out by the last build, read by keyboard navigation.
  List<Object> _items = const [];
  List<PaletteAction> _actions = const [];

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _move(int delta) {
    if (_actions.isEmpty) return;
    setState(
      () => _selectedIndex = (_selectedIndex + delta).clamp(
        0,
        _actions.length - 1,
      ),
    );
    _ensureSelectedVisible();
  }

  double _extentOf(Object item) =>
      item is String ? _groupHeaderHeight : _rowHeight;

  void _ensureSelectedVisible() {
    if (!_scrollController.hasClients) return;
    var top = 0.0;
    var seen = -1;
    for (final item in _items) {
      if (item is PaletteAction && ++seen == _selectedIndex) break;
      top += _extentOf(item);
    }
    final bottom = top + _rowHeight;
    final position = _scrollController.position;
    var target = position.pixels;
    if (top < target) {
      target = top;
    } else if (bottom > target + position.viewportDimension) {
      target = bottom - position.viewportDimension;
    }
    _scrollController.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  Future<void> _execute(PaletteAction action) async {
    if (_executing) return;
    if (action.opensSessionPicker) {
      setState(() {
        _sessionMode = true;
        _searchController.clear();
        _selectedIndex = 0;
      });
      return;
    }
    _executing = true;
    // Close first so the command never runs behind this palette or stacks a
    // dialog on top of it. Commands use the host context and ref, which
    // outlive this palette.
    Navigator.of(context).pop();
    final host = widget.hostContext;
    try {
      await action.onExecute();
    } catch (error) {
      if (host.mounted) {
        FrameSnackBar.show(
          host,
          message: widget.hostRef
              .read(appStringsProvider)
              .actionFailedNotice(error),
        );
      }
    }
  }

  /// Subsequence match: every character of [query] appears in [text], in order.
  static bool _fuzzyMatches(String text, String query) {
    final target = text.toLowerCase();
    var index = 0;
    for (var i = 0; i < target.length && index < query.length; i++) {
      if (target.codeUnitAt(i) == query.codeUnitAt(index)) index++;
    }
    return index == query.length;
  }

  List<PaletteAction> _sessionActions(String query) {
    final sessions = ref.watch(sessionListProvider).value ?? const [];
    final names = ref.watch(sessionDisplayNamesProvider);
    final matches = <({PaletteAction action, bool prefix})>[];
    for (final session in sessions) {
      final id = (session['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final name = names[id] ?? (session['name'] ?? '').toString();
      final lower = name.toLowerCase();
      if (query.isNotEmpty && !_fuzzyMatches(lower, query)) continue;
      matches.add((
        action: PaletteAction(
          id: 'session_$id',
          group: '',
          title: name,
          subtitle: (session['cwd'] ?? '').toString(),
          icon: Icons.chat_bubble_outline,
          onExecute: () async {
            final host = widget.hostContext;
            final hostRef = widget.hostRef;
            if (await switchSessionSafely(host, hostRef, id) &&
                host.mounted) {
              hostRef.read(activeSessionIdProvider.notifier).state = id;
            }
          },
        ),
        prefix: query.isNotEmpty && lower.contains(query),
      ));
    }
    // Substring hits first; fuzzy-only hits keep the list order.
    matches.sort((a, b) => (b.prefix ? 1 : 0) - (a.prefix ? 1 : 0));
    return [for (final match in matches) match.action];
  }

  List<PaletteAction> _commandActions(BuildContext context) {
    final host = widget.hostContext;
    final hostRef = widget.hostRef;
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final strings = ref.watch(appStringsProvider);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final activeState = activeSessionId == null
        ? null
        : ref.watch(sessionStateFamily(activeSessionId));
    final canWrite = activeState != null && !activeState.readOnly;
    final isReviewing = ref.watch(isReviewingChangesProvider);
    final macOS = defaultTargetPlatform == TargetPlatform.macOS;
    final modifier = strings.paletteModifierKeyLabel(macOS: macOS);
    final shift = strings.paletteShiftKeyLabel(macOS: macOS);

    final sessionGroup = strings.paletteGroupSession;
    final viewGroup = strings.paletteGroupView;
    final gitGroup = strings.paletteGroupGit;
    final settingsGroup = strings.paletteGroupSettings;

    return [
      PaletteAction(
        id: 'new_session',
        group: sessionGroup,
        title: strings.paletteNewSessionTitle,
        subtitle: strings.paletteNewSessionSubtitle,
        icon: Icons.add_circle_outline,
        onExecute: () async {
          final client = hostRef.read(pcpClientProvider);
          if (client == null) return;
          await createSession(
            host,
            hostRef,
            name: strings.isItalian ? 'Nuova Sessione' : 'New Session',
          );
          if (!host.mounted) return;
          hostRef.invalidate(sessionListProvider);
        },
      ),
      PaletteAction(
        id: 'go_to_session',
        group: sessionGroup,
        title: strings.paletteGoToSessionTitle,
        subtitle: strings.paletteGoToSessionSubtitle,
        icon: Icons.manage_search,
        opensSessionPicker: true,
        onExecute: () async {},
      ),
      if (canWrite && activeSessionId != null) ...[
        PaletteAction(
          id: 'compact',
          group: sessionGroup,
          title: strings.paletteCompactTitle,
          subtitle: strings.paletteCompactSubtitle,
          icon: Icons.compress,
          onExecute: () async {
            await hostRef
                .read(sessionStateFamily(activeSessionId).notifier)
                .compact();
          },
        ),
        PaletteAction(
          id: 'clear_queue',
          group: sessionGroup,
          title: strings.paletteClearQueueTitle,
          subtitle: strings.paletteClearQueueSubtitle,
          icon: Icons.clear_all,
          onExecute: () async {
            await hostRef
                .read(sessionStateFamily(activeSessionId).notifier)
                .clearQueue();
          },
        ),
      ],
      // Esc only interrupts while the composer has focus, so no key cap here.
      if (activeSessionId != null &&
          activeState != null &&
          activeState.isStreaming)
        PaletteAction(
          id: 'interrupt',
          group: sessionGroup,
          title: strings.paletteInterruptTitle,
          subtitle: strings.paletteInterruptSubtitle,
          icon: Icons.stop_circle_outlined,
          onExecute: () async {
            await hostRef
                .read(sessionStateFamily(activeSessionId).notifier)
                .interrupt();
          },
        ),
      if (!kIsWeb && activeSessionId != null)
        PaletteAction(
          id: 'new_terminal',
          group: sessionGroup,
          title: strings.paletteNewTerminalTitle,
          subtitle: strings.paletteNewTerminalSubtitle,
          icon: Icons.terminal,
          onExecute: () async {
            final terminal = hostRef.read(terminalSettingsProvider);
            final cwd = hostRef.read(sessionStateFamily(activeSessionId)).cwd;
            final launched = await launchNativeTerminal(
              cwd: cwd,
              nativeApp: terminal.nativeApp,
              customPath: terminal.customPath,
            );
            if (!launched && host.mounted) {
              FrameSnackBar.show(
                host,
                message: hostRef
                    .read(appStringsProvider)
                    .actionFailedNotice(strings.paletteNewTerminalTitle),
              );
            }
          },
        ),
      if (activeSessionId != null)
        PaletteAction(
          id: 'toggle_side_panel',
          group: viewGroup,
          title: strings.sideToggleActionTitle,
          subtitle: strings.sideToggleActionSubtitle,
          icon: Icons.call_split,
          keys: [modifier, shift, 'B'],
          onExecute: () async {
            hostRef
                .read(sideThreadFamily(activeSessionId).notifier)
                .togglePanel();
          },
        ),
      if (widget.onTogglePane != null && widget.isPaneVisible != null)
        for (final pane in WorkspacePane.values)
          if (!(widget.isPaneVisible!(pane) &&
              WorkspacePane.values.where(widget.isPaneVisible!).length <= 1))
            _paneAction(pane, viewGroup, strings),
      PaletteAction(
        id: 'toggle_theme',
        group: viewGroup,
        title: isLight ? strings.darkThemeTooltip : strings.lightThemeTooltip,
        subtitle: strings.paletteThemeSubtitle,
        icon: isLight ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
        onExecute: () async {
          hostRef
              .read(activeThemeSpecProvider.notifier)
              .setTheme(isLight ? 'piframe-dark' : 'piframe-light');
        },
      ),
      if (ref.watch(browserPaneSupportedProvider))
        PaletteAction(
          id: 'switch_to_browser',
          group: viewGroup,
          title: strings.paletteSwitchBrowserTitle,
          subtitle: strings.paletteSwitchBrowserSubtitle,
          icon: Icons.language_outlined,
          onExecute: () async {
            hostRef.read(rightPaneModeProvider.notifier).state =
                RightPaneMode.browser;
          },
        ),
      if (ref.watch(browserPaneSupportedProvider))
        PaletteAction(
          id: 'switch_to_git',
          group: viewGroup,
          title: strings.paletteSwitchGitTitle,
          subtitle: strings.paletteSwitchGitSubtitle,
          icon: Icons.source_outlined,
          onExecute: () async {
            hostRef.read(rightPaneModeProvider.notifier).state =
                RightPaneMode.git;
          },
        ),
      if (activeSessionId != null && !isReviewing)
        PaletteAction(
          id: 'review_changes',
          group: gitGroup,
          title: strings.paletteReviewChangesTitle,
          subtitle: strings.paletteReviewChangesSubtitle,
          icon: Icons.rate_review_outlined,
          onExecute: () async {
            hostRef.read(isReviewingChangesProvider.notifier).state = true;
          },
        ),
      if (canWrite && activeSessionId != null) ...[
        for (final (id, title, subtitle, icon) in [
          (
            'git_fetch',
            strings.paletteGitFetchTitle,
            strings.paletteGitFetchSubtitle,
            Icons.cloud_download_outlined,
          ),
          (
            'git_pull',
            strings.paletteGitPullTitle,
            strings.paletteGitPullSubtitle,
            Icons.arrow_downward,
          ),
          (
            'git_push',
            strings.paletteGitPushTitle,
            strings.paletteGitPushSubtitle,
            Icons.arrow_upward,
          ),
        ])
          PaletteAction(
            id: id,
            group: gitGroup,
            title: title,
            subtitle: subtitle,
            icon: icon,
            onExecute: () async {
              final client = hostRef.read(pcpClientProvider);
              if (client == null) return;
              await client.workspaceGitAction(activeSessionId, {
                'action': id.substring('git_'.length),
                'paths': const <String>[],
              });
            },
          ),
      ],
      if (widget.onOpenSettings != null)
        PaletteAction(
          id: 'settings',
          group: settingsGroup,
          title: strings.paletteSettingsTitle,
          subtitle: strings.paletteSettingsSubtitle,
          icon: Icons.settings,
          onExecute: () async {
            widget.onOpenSettings?.call();
          },
        ),
    ];
  }

  PaletteAction _paneAction(
    WorkspacePane pane,
    String group,
    AppStrings strings,
  ) {
    final name = switch (pane) {
      WorkspacePane.chat => strings.paletteChatPaneName,
      WorkspacePane.repository => strings.paletteRepositoryPaneName,
      WorkspacePane.git => strings.paletteGitPaneName,
    };
    final visible = widget.isPaneVisible!(pane);
    return PaletteAction(
      id: 'pane_${pane.name}',
      group: group,
      title: visible
          ? strings.paletteHidePaneTitle(name)
          : strings.paletteShowPaneTitle(name),
      subtitle: strings.paletteTogglePaneSubtitle(name),
      icon: switch (pane) {
        WorkspacePane.chat => Icons.chat_bubble_outline,
        WorkspacePane.repository => Icons.folder_outlined,
        WorkspacePane.git => Icons.source_outlined,
      },
      onExecute: () async => widget.onTogglePane!(pane),
    );
  }

  /// Flattens filtered actions into group headers and rows. With a query the
  /// list is flat, so matches are not split by group.
  List<Object> _layout(List<PaletteAction> actions, bool searching) {
    if (searching) return actions;
    final items = <Object>[];
    String? currentGroup;
    for (final action in actions) {
      if (action.group != currentGroup) {
        currentGroup = action.group;
        items.add(action.group);
      }
      items.add(action);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);
    final query = _searchController.text.trim().toLowerCase();

    final List<PaletteAction> actions;
    if (_sessionMode) {
      actions = _sessionActions(query);
    } else {
      actions = _commandActions(context).where((a) {
        return a.title.toLowerCase().contains(query) ||
            a.subtitle.toLowerCase().contains(query);
      }).toList();
    }
    _actions = actions;
    _items = _layout(actions, query.isNotEmpty || _sessionMode);
    if (_selectedIndex >= actions.length) {
      _selectedIndex = actions.isEmpty ? 0 : actions.length - 1;
    }

    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_actions.isNotEmpty) _execute(_actions[_selectedIndex]);
        },
      },
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _dialogMaxWidth,
            maxHeight: maxHeight,
          ),
          child: Material(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.radiusLg),
                border: Border.all(color: tokens.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search Input Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FrameSpace.x4,
                      vertical: FrameSpace.x3,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          size: FrameSize.iconLg,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(width: FrameSpace.x3),
                        Expanded(
                          // Standard keyboard focus ring. The field draws no
                          // border of its own, so the theme's focused input
                          // border cannot add a second box.
                          child: FrameFocusRing(
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                            child: TextField(
                              key: const ValueKey(
                                'command-palette-search-field',
                              ),
                              controller: _searchController,
                              autofocus: true,
                              style: text.bodyLarge.copyWith(
                                color: tokens.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: _sessionMode
                                    ? strings.paletteSessionSearchHint
                                    : strings.paletteSearchHint,
                                hintStyle: text.bodyLarge.copyWith(
                                  color: tokens.textMuted,
                                ),
                                filled: false,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: FrameSpace.x2,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                              ),
                              onChanged: (_) =>
                                  setState(() => _selectedIndex = 0),
                            ),
                          ),
                        ),
                        _KeyCap(label: strings.paletteEscKeyLabel),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: tokens.border),

                  // Results list: sized to its content, capped by the dialog.
                  Flexible(
                    child: _items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(_emptyStatePadding),
                            child: Center(
                              child: Text(
                                _sessionMode
                                    ? strings.paletteNoSessionsFound
                                    : strings.paletteNoActionsFound,
                                style: text.body.copyWith(
                                  color: tokens.textMuted,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            key: const ValueKey('command-palette-list'),
                            shrinkWrap: true,
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              vertical: FrameSpace.x1,
                            ),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              if (item is String) {
                                return _GroupHeader(label: item, tokens: tokens);
                              }
                              final action = item as PaletteAction;
                              final isSelected =
                                  _actions.indexOf(action) == _selectedIndex;
                              return _ActionRow(
                                action: action,
                                isSelected: isSelected,
                                tokens: tokens,
                                onTap: () => _execute(action),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final FrameTokens tokens;

  const _GroupHeader({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _groupHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label.toUpperCase(),
            style: FrameText.of(context).caption.copyWith(
              color: tokens.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final PaletteAction action;
  final bool isSelected;
  final FrameTokens tokens;
  final VoidCallback onTap;

  const _ActionRow({
    required this.action,
    required this.isSelected,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = FrameText.of(context);
    return InkWell(
      key: ValueKey('palette-action-${action.id}'),
      onTap: onTap,
      hoverColor: tokens.surface,
      child: Container(
        height: _rowHeight,
        color: isSelected ? tokens.accent.withValues(alpha: 0.1) : null,
        padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x4),
        child: Row(
          children: [
            Icon(
              action.icon,
              size: _rowIconSize,
              color: isSelected ? tokens.accent : tokens.textSecondary,
            ),
            const SizedBox(width: _rowIconGap),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.body.copyWith(
                      color: tokens.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Text(
                    action.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.caption.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            if (action.keys.isNotEmpty) ...[
              const SizedBox(width: FrameSpace.x3),
              Row(
                key: ValueKey('palette-keys-${action.id}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final key in action.keys) ...[
                    const SizedBox(width: FrameSpace.x1),
                    _KeyCap(label: key),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  final String label;

  const _KeyCap({required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FrameSpace.x2,
        vertical: FrameSpace.x1,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        label,
        style: FrameText.of(context).mono.copyWith(
          color: tokens.textMuted,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
