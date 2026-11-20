import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../app/row_context_menu.dart';
import 'instruction_file_dialog.dart';
import 'session_actions.dart';
import 'session_titles.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../ui/frame_activity_indicator.dart';
import '../../ui/frame_icon_action.dart';
import '../../ui/frame_list_row.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/motion.dart';
import '../session_tree/session_tree_dialog.dart';
import '../transcript/workflows_provider.dart';
import '../workspace/repository_workspace.dart';
import 'pinned_sessions_provider.dart';
import 'removed_repos_provider.dart';
import 'unread_sessions_provider.dart';
import '../../domain/session/agent_status.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_shell.dart';
import '../../domain/session/session_labels.dart';
import '../../data/update/update_providers.dart';
import '../../data/platform/widget_test_binding.dart';

/// Session rows in the rail are denser than the shared list row (plan 5.1).
const double _railRowMinHeight = 32;

/// Persistent user state for explicitly expanded session repo folders across unmounts/views.
final sessionFoldersExpandedProvider = StateProvider<Set<String>>((ref) => <String>{});

/// Persistent user state for explicitly collapsed session repo folders across unmounts/views.
final sessionFoldersCollapsedProvider = StateProvider<Set<String>>((ref) => <String>{});

bool _isSubsession(Map<String, dynamic> session) {
  if (session['isSubsession'] == true) return true;
  final parentSession = (session['parentSession'] ?? '').toString().trim();
  if (parentSession.isNotEmpty) return true;
  final name = (session['name'] ?? '').toString().toLowerCase();
  final id = (session['id'] ?? '').toString().toLowerCase();
  return name.contains('worker#') ||
      id.contains('worker#') ||
      name.contains('#') ||
      id.contains('#') ||
      name.startsWith('subagent') ||
      id.startsWith('subagent');
}

bool _isWorkerSession(Map<String, dynamic> session) => _isSubsession(session);

String _sessionFolder(Map<String, dynamic> session) => sessionFolder(session);

/// The session's name when the user or Pi chose it, else an empty string.
String _chosenNameOf(Map<String, dynamic> session) {
  final id = session['id'] as String? ?? '';
  final name = session['name'] as String?;
  return hasChosenSessionName(name, id) ? name!.trim() : '';
}

/// Repository to expand by default: the active session's, else the one with
/// the most recent activity.
String? _railDefaultFolder(List<Map<String, dynamic>> sessions, String? activeId) {
  Map<String, dynamic>? latest;
  var latestTime = -1.0;
  for (final session in sessions) {
    if (_isWorkerSession(session)) continue;
    if (activeId != null && session['id'] == activeId) {
      return _sessionFolder(session);
    }
    final time = (session['lastActivityAt'] as num?)?.toDouble() ?? 0;
    if (time > latestTime) {
      latestTime = time;
      latest = session;
    }
  }
  return latest == null ? null : _sessionFolder(latest);
}

String _folderName(String path, [String fallback = 'Sessioni']) {
  final segments = path.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty);
  return segments.isEmpty ? fallback : segments.last;
}

class SessionsSidebar extends ConsumerStatefulWidget {
  final VoidCallback? onSessionSelected;
  final VoidCallback? onCollapse;

  const SessionsSidebar({super.key, this.onSessionSelected, this.onCollapse});

  @override
  ConsumerState<SessionsSidebar> createState() => _SessionsSidebarState();
}

/// One row of the rail in visible order, used by the keyboard handler.
class _RailRow {
  final String? folder;
  final String? sessionId;
  final String name;

  const _RailRow.folder(this.folder) : sessionId = null, name = '';

  const _RailRow.session({required this.sessionId, required this.folder, required this.name});

  bool get isFolder => sessionId == null;
}

class _SessionsSidebarState extends ConsumerState<SessionsSidebar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _railFocus = FocusNode(debugLabel: 'sessions-rail');
  String _searchQuery = '';
  String _filterMode = 'all'; // 'all', 'active', 'repo'
  bool _creating = false;
  // Repository expanded by default: the active session's, else the latest used.
  String? _defaultFolder;
  // Keyboard position in the rail, as a row key ('folder:<f>' or 'session:<id>').
  String? _cursorKey;
  // Context menus of the rows, opened by Shift+F10 or the Menu key on the cursor.
  final RowMenuRegistry _rowMenus = RowMenuRegistry();
  final Map<String, GlobalKey> _folderRowKeys = {};
  List<_RailRow> _railRows = const [];
  String? _railActiveId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _railFocus.addListener(_onRailFocusChanged);
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  void _onRailFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    if (mounted) setState(() {});
  }

  /// The cursor ring is a keyboard cue: after a click it would sit on the
  /// clicked card while the selection (and a cancelled switch) sat elsewhere.
  bool _showsCursor(String key) =>
      _railFocus.hasFocus && FocusManager.instance.highlightMode == FocusHighlightMode.traditional && _cursorKey == key;

  @override
  void dispose() {
    _searchController.dispose();
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    _railFocus.removeListener(_onRailFocusChanged);
    _railFocus.dispose();
    super.dispose();
  }

  Future<void> _startNewSession() async {
    if (_creating || ref.read(pcpClientProvider) == null) return;
    setState(() => _creating = true);
    await createSession(context, ref);
    if (mounted) {
      setState(() => _creating = false);
      widget.onSessionSelected?.call();
    }
  }

  bool _isFolderExpanded(String folder) {
    if (_searchQuery.isNotEmpty) return true;
    final expanded = ref.watch(sessionFoldersExpandedProvider);
    if (expanded.contains(folder)) return true;
    final collapsed = ref.watch(sessionFoldersCollapsedProvider);
    return folder == _defaultFolder && !collapsed.contains(folder);
  }

  void _setFolderExpanded(String folder, bool isExpanded) {
    if (isExpanded) {
      ref.read(sessionFoldersExpandedProvider.notifier).update((s) => {...s, folder});
      ref.read(sessionFoldersCollapsedProvider.notifier).update((s) => s.where((f) => f != folder).toSet());
    } else {
      ref.read(sessionFoldersExpandedProvider.notifier).update((s) => s.where((f) => f != folder).toSet());
      ref.read(sessionFoldersCollapsedProvider.notifier).update((s) => {...s, folder});
    }
  }

  KeyEventResult _onRailKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = _railRows;
    if (rows.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    var index = rows.indexWhere((r) => _rowKey(r) == _cursorKey);
    if (index < 0) {
      index = rows.indexWhere((r) => r.sessionId != null && r.sessionId == _railActiveId);
      if (index < 0) index = 0;
    }
    final current = rows[index];

    void moveTo(int i) {
      setState(() => _cursorKey = _rowKey(rows[i]));
    }

    if (isContextMenuKey(event)) {
      _rowMenus.openFor(_rowKey(current));
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      moveTo((index + 1).clamp(0, rows.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      moveTo((index - 1).clamp(0, rows.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (current.isFolder) {
        final expanded = _isFolderExpanded(current.folder!);
        if (!expanded) {
          _setFolderExpanded(current.folder!, true);
        } else if (index + 1 < rows.length) {
          moveTo(index + 1);
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (current.isFolder) {
        if (_isFolderExpanded(current.folder!)) {
          _setFolderExpanded(current.folder!, false);
        }
      } else {
        final parent = rows.indexWhere((r) => r.isFolder && r.folder == current.folder);
        if (parent >= 0) moveTo(parent);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (current.isFolder) {
        final folder = current.folder!;
        _setFolderExpanded(folder, !_isFolderExpanded(folder));
      } else {
        _openSession(current.sessionId!);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2 && !current.isFolder) {
      _showRenameDialog(current.sessionId!, current.name);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _rowKey(_RailRow row) => row.isFolder ? 'folder:${row.folder}' : 'session:${row.sessionId}';

  Future<void> _openSession(String id) async {
    setState(() => _cursorKey = 'session:$id');
    if (await switchSessionSafely(context, ref, id)) {
      widget.onSessionSelected?.call();
    }
  }

  Future<void> _showRenameDialog(String sessionId, String currentName) async {
    final tokens = context.tokens;
    final strings = ref.read(appStringsProvider);
    final textController = TextEditingController(text: currentName);

    String? newName;
    try {
      newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            side: BorderSide(color: tokens.border, width: 1),
          ),
          title: Text(
            strings.renameSessionDialogTitle,
            style: FrameText.of(ctx).title.copyWith(color: tokens.textPrimary),
          ),
          content: TextField(
            controller: textController,
            autofocus: true,
            style: FrameText.of(ctx).body.copyWith(color: tokens.textPrimary),
            decoration: InputDecoration(
              hintText: strings.sessionNameHint,
              hintStyle: FrameText.of(ctx).body.copyWith(color: tokens.textMuted),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: tokens.border),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: tokens.accent),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
            ),
            onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(strings.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: tokens.accent, foregroundColor: tokens.surface),
              onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
              child: Text(strings.save),
            ),
          ],
        ),
      );
    } finally {
      textController.dispose();
    }

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      final client = ref.read(pcpClientProvider);
      if (client != null) {
        try {
          await client.renameSession(sessionId, newName);
          ref.invalidate(sessionListProvider);
          if (mounted) {
            FrameSnackBar.show(context, message: strings.sessionRenamedNotice(newName));
          }
        } catch (e) {
          if (mounted) {
            FrameSnackBar.show(
              context,
              message: strings.renameErrorNotice(e),
              isError: true,
              backgroundColor: tokens.danger,
            );
          }
        }
      }
    }
  }

  Future<void> _cloneSession(String sessionId) async {
    final tokens = context.tokens;
    final strings = ref.read(appStringsProvider);
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    if (!await resolveDirtyRepository(context, ref, ref.read(activeSessionIdProvider))) {
      return;
    }

    try {
      final res = await client.cloneSession(sessionId);
      if (!mounted || !context.mounted) return;
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final newSid = data['sessionId'] as String? ?? data['id'] as String?;
      if (newSid != null) {
        if (!await switchSessionSafely(context, ref, newSid)) return;
        ref.invalidate(sessionListProvider);
        if (mounted) {
          FrameSnackBar.show(context, message: strings.sessionDuplicatedNotice(newSid));
        }
      }
    } catch (e) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: strings.duplicateErrorNotice(e),
          isError: true,
          backgroundColor: tokens.danger,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);
    final sessionsAsync = ref.watch(sessionListProvider);
    final activeId = ref.watch(activeSessionIdProvider);
    final activeSessionCwd = activeId != null ? ref.watch(sessionStateFamily(activeId).select((s) => s.cwd)) : '';

    return Container(
      decoration: BoxDecoration(color: tokens.surface),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    strings.sidebarTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.heading.copyWith(color: tokens.textPrimary, fontFamily: tokens.headingFontFamily),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh_outlined, color: tokens.textMuted, size: FrameSize.iconLg),
                  tooltip: strings.refreshSessionsTooltip,
                  onPressed: () {
                    ref.invalidate(sessionListProvider);
                    final active = ref.read(activeSessionIdProvider);
                    if (active != null) {
                      ref.read(pcpClientProvider)?.attach(active);
                    }
                  },
                ),
                IconButton(
                  icon: Icon(Icons.add_outlined, color: tokens.accent, size: FrameSize.iconLg),
                  tooltip: strings.newSessionTooltip,
                  onPressed: _creating || ref.watch(pcpClientProvider) == null
                      ? null
                      : () async {
                          setState(() => _creating = true);
                          await createSession(context, ref);
                          if (mounted) {
                            setState(() => _creating = false);
                            widget.onSessionSelected?.call();
                          }
                        },
                ),
                if (widget.onCollapse != null)
                  IconButton(
                    icon: Icon(Icons.chevron_left_outlined, color: tokens.textMuted, size: FrameSize.iconLg),
                    tooltip: strings.collapseSidebarTooltip,
                    onPressed: widget.onCollapse,
                  ),
              ],
            ),
          ),

          // Search Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3, vertical: FrameSpace.x2),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
            ),
            child: TextField(
              controller: _searchController,
              style: text.label.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w400),
              decoration: InputDecoration(
                isDense: true,
                hintText: strings.searchSessionsHint,
                hintStyle: text.label.copyWith(color: tokens.textMuted, fontWeight: FontWeight.w400),
                prefixIcon: Icon(Icons.search_outlined, size: FrameSize.icon, color: tokens.textMuted),
                prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_outlined, size: FrameSize.icon, color: tokens.textMuted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: tokens.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  borderSide: BorderSide(color: tokens.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  borderSide: BorderSide(color: tokens.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  borderSide: BorderSide(color: tokens.accent),
                ),
              ),
            ),
          ),

          // Filter: left-aligned segmented control over a full-width divider
          Container(
            padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3, vertical: FrameSpace.x1),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              // Wrap at large text scales so no filter is cut off; scroll otherwise.
              child: MediaQuery.textScalerOf(context).scale(1) > 1.3
                  ? Wrap(
                      spacing: FrameSpace.x1,
                      children: [
                        _buildFilterChip('all', strings.filterAll, tokens),
                        _buildFilterChip('active', strings.filterActive, tokens),
                        _buildFilterChip('repo', strings.filterRepo, tokens),
                      ],
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('all', strings.filterAll, tokens),
                          _buildFilterChip('active', strings.filterActive, tokens),
                          _buildFilterChip('repo', strings.filterRepo, tokens),
                        ],
                      ),
                    ),
            ),
          ),

          // Session list
          Expanded(
            child: sessionsAsync.when(
              data: (allSessions) {
                final removedRepos = ref.watch(removedReposProvider);
                final folderNames = folderDisplayNames(
                  allSessions.where((s) => !_isWorkerSession(s)).map(_sessionFolder),
                );
                _railActiveId = activeId;
                final sessionNames = ref.watch(sessionDisplayNamesProvider);
                _defaultFolder = _railDefaultFolder(allSessions, activeId);

                // Apply search and filter
                final filtered = allSessions.where((s) {
                  if (_isWorkerSession(s)) return false;
                  final folder = _sessionFolder(s);
                  if (_searchQuery.isEmpty && removedRepos.contains(folder)) {
                    return false;
                  }
                  final id = (s['id'] as String? ?? '').toLowerCase();
                  final name = (s['name'] as String? ?? '').toLowerCase();
                  final cwd = (s['cwd'] as String? ?? '').toLowerCase();
                  final preview = (s['lastMessagePreview'] as String? ?? '').toLowerCase();
                  final isActive = s['isActive'] == true;

                  // Text search
                  if (_searchQuery.isNotEmpty) {
                    final match =
                        id.contains(_searchQuery) ||
                        name.contains(_searchQuery) ||
                        cwd.contains(_searchQuery) ||
                        preview.contains(_searchQuery);
                    if (!match) return false;
                  }

                  // Mode filter
                  if (_filterMode == 'active' && !isActive) {
                    return false;
                  }
                  if (_filterMode == 'repo' && activeSessionCwd.isNotEmpty) {
                    var activeGroup = activeSessionCwd;
                    for (final candidate in allSessions) {
                      if (candidate['id'] == activeId) {
                        activeGroup = _sessionFolder(candidate);
                        break;
                      }
                    }
                    if (_sessionFolder(s) != activeGroup) return false;
                  }

                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  // One action per empty state: clear the search when a
                  // search has no match, show all when only the mode filter
                  // hides everything, otherwise start a new session.
                  final String message;
                  final String actionLabel;
                  final Key actionKey;
                  final VoidCallback? onAction;
                  if (_searchQuery.isNotEmpty) {
                    message = strings.noSessionsMatchFilters;
                    actionLabel = strings.clearSearchAction;
                    actionKey = const ValueKey('sessions-empty-clear-search');
                    onAction = () => _searchController.clear();
                  } else if (_filterMode != 'all') {
                    message = strings.noSessionsMatchFilters;
                    actionLabel = strings.showAllSessionsAction;
                    actionKey = const ValueKey('sessions-empty-show-all');
                    onAction = () => setState(() => _filterMode = 'all');
                  } else {
                    message = strings.noSessionsFound;
                    actionLabel = strings.newSessionAction;
                    actionKey = const ValueKey('sessions-empty-new-session');
                    onAction = _creating || ref.watch(pcpClientProvider) == null ? null : _startNewSession;
                  }
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(FrameSpace.x4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            message,
                            style: text.label.copyWith(color: tokens.textMuted),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: FrameSpace.x2),
                          TextButton(
                            key: actionKey,
                            style: TextButton.styleFrom(foregroundColor: tokens.accent),
                            onPressed: onAction,
                            child: Text(actionLabel),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final pinnedIds = ref.watch(pinnedSessionsProvider);
                final unreadIds = ref.watch(unreadSessionsProvider);
                final sessionMap = {
                  for (final s in allSessions)
                    if (s['id'] is String) s['id'] as String: s,
                };
                final pinnedSessions = <Map<String, dynamic>>[];
                for (final id in pinnedIds) {
                  final s = sessionMap[id];
                  if (s == null) continue;
                  if (_isWorkerSession(s)) continue;
                  final folder = _sessionFolder(s);
                  if (_searchQuery.isEmpty && removedRepos.contains(folder)) {
                    continue;
                  }
                  pinnedSessions.add(s);
                }

                final activeFolders = <String>{};
                for (final s in allSessions) {
                  if (s['isActive'] == true) {
                    activeFolders.add(_sessionFolder(s));
                  }
                }

                final grouped = <String, List<Map<String, dynamic>>>{};
                for (final session in filtered) {
                  grouped.putIfAbsent(_sessionFolder(session), () => []).add(session);
                }
                final folderRows = <({String? folder, Map<String, dynamic>? session, bool isFolder})>[];

                for (final group in grouped.entries) {
                  folderRows.add((folder: group.key, session: null, isFolder: true));
                  final isExpanded = _isFolderExpanded(group.key);
                  if (isExpanded) {
                    folderRows.addAll(group.value.map((session) => (folder: null, session: session, isFolder: false)));
                  }
                }

                final showPinnedSection = _searchQuery.isEmpty && _filterMode == 'all' && pinnedSessions.isNotEmpty;

                _railRows = [
                  if (showPinnedSection)
                    for (final s in pinnedSessions)
                      _RailRow.session(
                        sessionId: s['id'] as String? ?? '',
                        folder: _sessionFolder(s),
                        name: _chosenNameOf(s),
                      ),
                  for (final row in folderRows)
                    if (row.isFolder)
                      _RailRow.folder(row.folder)
                    else
                      _RailRow.session(
                        sessionId: row.session!['id'] as String? ?? '',
                        folder: _sessionFolder(row.session!),
                        name: _chosenNameOf(row.session!),
                      ),
                ];

                Widget buildPinnedHeader() {
                  final hasUnreadPinned = pinnedSessions.any((s) => s['id'] != activeId && unreadIds.contains(s['id']));

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(FrameSpace.x2, FrameSpace.x2, FrameSpace.x2, FrameSpace.x1),
                    child: Row(
                      children: [
                        Icon(Icons.push_pin_outlined, size: FrameSize.icon, color: tokens.accent),
                        const SizedBox(width: 6),
                        Text(
                          strings.pinnedSessionsHeader(pinnedSessions.length),
                          style: text.caption.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (hasUnreadPinned) ...[
                          const SizedBox(width: 6),
                          const _UnreadDot(key: ValueKey('pinned-unread-dot'), unread: true, size: 6),
                        ],
                      ],
                    ),
                  );
                }

                return Focus(
                  focusNode: _railFocus,
                  onKeyEvent: _onRailKey,
                  child: CustomScrollView(
                    slivers: [
                      if (showPinnedSection) ...[
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(FrameSpace.x2, FrameSpace.x1, FrameSpace.x2, 0),
                          sliver: SliverToBoxAdapter(child: buildPinnedHeader()),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(FrameSpace.x2, 0, FrameSpace.x2, FrameSpace.x1),
                          sliver: SliverReorderableList(
                            itemCount: pinnedSessions.length,
                            proxyDecorator: (child, index, animation) {
                              return Material(
                                elevation: 4,
                                color: tokens.surfaceElevated,
                                borderRadius: BorderRadius.circular(tokens.radiusSm),
                                child: child,
                              );
                            },
                            onReorderItem: (oldIndex, newIndex) {
                              if (oldIndex < 0 || oldIndex >= pinnedSessions.length) {
                                return;
                              }
                              final movedId = pinnedSessions[oldIndex]['id'] as String? ?? '';
                              if (movedId.isEmpty) {
                                return;
                              }
                              ref.read(pinnedSessionsProvider.notifier).reorderById(movedId, newIndex);
                            },
                            itemBuilder: (rowContext, index) {
                              final s = pinnedSessions[index];
                              final id = s['id'] as String? ?? 's';
                              final isSelected = id == activeId;
                              return ReorderableDelayedDragStartListener(
                                key: ValueKey('pinned_session_$id'),
                                index: index,
                                child: _SessionTile(
                                  session: s,
                                  isPinned: true,
                                  qualifiedName: sessionNames[id],
                                  isPinnedSection: true,
                                  isSelected: isSelected,
                                  onMenuOpener: (open) => _rowMenus.register('session:$id', open),
                                  isCursor: _showsCursor('session:$id'),
                                  onTap: () {
                                    _railFocus.requestFocus();
                                    _openSession(id);
                                  },
                                  onPinToggle: () => ref.read(pinnedSessionsProvider.notifier).togglePin(id),
                                  onRename: (sId, sName) => _showRenameDialog(sId, sName),
                                  onTree: (sId) => SessionTreeDialog.show(context, sessionId: sId),
                                  onClone: (sId) => _cloneSession(sId),
                                  onDelete: (sId, sName) =>
                                      deleteSessionWithConfirmation(context, ref, sessionId: sId, sessionName: sName),
                                ),
                              );
                            },
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            key: const ValueKey('pinned-sessions-separator'),
                            padding: const EdgeInsets.fromLTRB(
                              FrameSpace.x2,
                              FrameSpace.x1,
                              FrameSpace.x2,
                              FrameSpace.x2,
                            ),
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                color: tokens.borderStrong,
                                borderRadius: BorderRadius.circular(tokens.radiusSm),
                              ),
                            ),
                          ),
                        ),
                      ],
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(FrameSpace.x2, 0, FrameSpace.x2, FrameSpace.x1),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((rowContext, index) {
                            final row = folderRows[index];
                            if (row.isFolder) {
                              final folder = row.folder ?? '';
                              final expanded = _isFolderExpanded(folder);
                              final folderSessions = grouped[folder] ?? [];
                              final hasUnread = folderSessions.any(
                                (s) => s['id'] != activeId && unreadIds.contains(s['id']),
                              );
                              final hasWorking = folderSessions.any((s) {
                                final sId = s['id'] as String? ?? '';
                                final isSel = sId == activeId;
                                final isPin = pinnedIds.contains(sId);
                                final isAct = s['isActive'] == true;
                                // Same rule as the session rows: a session opened in
                                // this run is followed live after switching away.
                                final isFollowed = ref.read(unreadSessionsProvider.notifier).isFollowed(sId);
                                if (isSel || isPin || isAct || isFollowed) {
                                  final isWorking =
                                      ref.watch(
                                        sessionStateFamily(sId).select(
                                          (st) =>
                                              st.agentStatus == AgentStatus.working ||
                                              st.agentStatus == AgentStatus.retrying ||
                                              st.agentStatus == AgentStatus.compacting ||
                                              st.isStreaming ||
                                              st.activeToolCalls.isNotEmpty,
                                        ),
                                      ) ||
                                      ref.watch(backgroundAgentsRunningProvider(sId));
                                  if (isWorking) {
                                    return true;
                                  }
                                }
                                return s['status'] == 'working' || s['isStreaming'] == true;
                              });

                              Widget folderTile = ListTile(
                                key: ValueKey('session-folder:$folder'),
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                minLeadingWidth: 18,
                                contentPadding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2),
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
                                      size: FrameSize.icon,
                                      color: hasWorking ? tokens.agentWorking : tokens.accent.withValues(alpha: 0.8),
                                    ),
                                    if (hasWorking) ...[
                                      const SizedBox(width: FrameSpace.x1),
                                      Container(
                                        key: ValueKey('folder-working-dot:$folder'),
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(shape: BoxShape.circle, color: tokens.agentWorking),
                                      ),
                                    ] else if (hasUnread) ...[
                                      const SizedBox(width: FrameSpace.x1),
                                      _UnreadDot(key: ValueKey('folder-unread-dot:$folder'), unread: true, size: 6),
                                    ] else ...[
                                      // Same width as a dot, so the name does not
                                      // shift when work starts or an answer lands.
                                      const SizedBox(width: FrameSpace.x1 + 6),
                                    ],
                                  ],
                                ),
                                title: Text(
                                  folder.isEmpty
                                      ? strings.sidebarFallbackFolderLabel
                                      : (folderNames[folder] ?? _folderName(folder)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.label.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  folder.isEmpty ? strings.unknownFolderLabel : folder,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.caption.copyWith(color: tokens.textMuted),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FrameIconAction(
                                      key: ValueKey('repo-new-session-btn-$folder'),
                                      icon: Icons.add_outlined,
                                      tooltip: strings.newSessionInFolderTooltip,
                                      onPressed: () async {
                                        _setFolderExpanded(folder, true);
                                        await createSession(context, ref, cwd: folder);
                                        if (mounted) widget.onSessionSelected?.call();
                                      },
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      expanded ? Icons.expand_more_outlined : Icons.chevron_right_outlined,
                                      size: FrameSize.icon,
                                      color: tokens.textMuted,
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  _railFocus.requestFocus();
                                  setState(() => _cursorKey = 'folder:$folder');
                                  _setFolderExpanded(folder, !expanded);
                                },
                              );

                              // The ListTile above keeps keyboard focus and primary taps;
                              // this InkWell only adds the right-click menu, so it is not a
                              // second Tab stop.
                              Future<void> openFolderMenu(Rect anchor) async {
                                final action = await showMenu<String>(
                                  context: context,
                                  color: tokens.surfaceElevated,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                                    side: BorderSide(color: tokens.border),
                                  ),
                                  position: menuPositionFor(context, anchor),
                                  items: [
                                    PopupMenuItem(
                                      value: 'instructions',
                                      height: 32,
                                      padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.description_outlined,
                                            size: FrameSize.icon,
                                            color: tokens.textSecondary,
                                          ),
                                          const SizedBox(width: FrameSpace.x2),
                                          Flexible(
                                            child: Text(
                                              strings.repoInstructionsAction,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: text.label.copyWith(color: tokens.textPrimary),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'new_session',
                                      height: 32,
                                      padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.add_outlined, size: FrameSize.icon, color: tokens.accent),
                                          const SizedBox(width: FrameSpace.x2),
                                          Flexible(
                                            child: Text(
                                              strings.newSessionAction,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: text.label.copyWith(color: tokens.textPrimary),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuDivider(height: 1),
                                    PopupMenuItem(
                                      value: 'remove_repo',
                                      height: 32,
                                      padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.close_outlined, size: FrameSize.icon, color: tokens.danger),
                                          const SizedBox(width: FrameSpace.x2),
                                          Flexible(
                                            child: Text(
                                              strings.removeRepoFromSidebarAction,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: text.label.copyWith(color: tokens.danger),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );

                                if (!context.mounted || action == null) return;
                                if (action == 'instructions') {
                                  final activeSid = activeFolders.contains(folder) ? activeId : null;
                                  InstructionFileDialog.show(context, folder: folder, sessionId: activeSid);
                                } else if (action == 'new_session') {
                                  _setFolderExpanded(folder, true);
                                  await createSession(context, ref, cwd: folder);
                                  if (mounted) widget.onSessionSelected?.call();
                                } else if (action == 'remove_repo') {
                                  removeRepoWithConfirmation(
                                    context,
                                    ref,
                                    folder: folder,
                                    repoName: folderNames[folder] ?? _folderName(folder),
                                    folderSessions: folderSessions,
                                  );
                                }
                              }

                              final folderRowKey = _folderRowKeys.putIfAbsent(folder, GlobalKey.new);
                              _rowMenus.register('folder:$folder', () {
                                final rowContext = folderRowKey.currentContext;
                                if (rowContext == null) return;
                                openFolderMenu(rowAnchorRect(rowContext));
                              });
                              folderTile = InkWell(
                                key: folderRowKey,
                                canRequestFocus: false,
                                onSecondaryTapDown: (details) =>
                                    openFolderMenu(pointerAnchorRect(details.globalPosition)),
                                child: folderTile,
                              );

                              final folderCursor = _showsCursor('folder:$folder');
                              return Material(
                                color: tokens.surface,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                                    border: folderCursor ? Border.all(color: tokens.focusRing) : null,
                                  ),
                                  child: folderTile,
                                ),
                              );
                            }

                            final s = row.session!;
                            final id = s['id'] as String? ?? 's';
                            final isSelected = id == activeId;
                            final isPinned = pinnedIds.contains(id);

                            return _SessionTile(
                              session: s,
                              isPinned: isPinned,
                              qualifiedName: sessionNames[id],
                              isPinnedSection: false,
                              isSelected: isSelected,
                              onMenuOpener: (open) => _rowMenus.register('session:$id', open),
                              isCursor: _showsCursor('session:$id'),
                              onTap: () {
                                _railFocus.requestFocus();
                                _openSession(id);
                              },
                              onPinToggle: () => ref.read(pinnedSessionsProvider.notifier).togglePin(id),
                              onRename: (sId, sName) => _showRenameDialog(sId, sName),
                              onTree: (sId) => SessionTreeDialog.show(context, sessionId: sId),
                              onClone: (sId) => _cloneSession(sId),
                              onDelete: (sId, sName) =>
                                  deleteSessionWithConfirmation(context, ref, sessionId: sId, sessionName: sName),
                            );
                          }, childCount: folderRows.length),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => Center(
                child: FrameActivityIndicator(size: FrameSize.iconLg, color: tokens.accent, strokeWidth: 2),
              ),
              error: (err, _) => Center(
                child: Text(strings.sidebarErrorNotice(err), style: text.label.copyWith(color: tokens.danger)),
              ),
            ),
          ),

          // Bottom utility bar: Settings
          Container(
            padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3, vertical: FrameSpace.x2),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.border, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2, vertical: 6),
                      alignment: Alignment.centerLeft,
                    ),
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.settings_outlined, size: FrameSize.icon),
                        if (ref.watch(hasUpdateBadgeProvider))
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(color: tokens.accent, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                    label: Text(strings.settingsLabel, style: text.label),
                    onPressed: () {
                      ref.read(showSettingsProvider.notifier).state = true;
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String mode, String label, FrameTokens tokens) {
    final isSelected = _filterMode == mode;
    final text = FrameText.of(context);
    return Semantics(
      selected: isSelected,
      button: true,
      child: InkWell(
        key: ValueKey('sessions-filter-$mode'),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        onTap: () => setState(() => _filterMode = mode),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: FrameSize.hitMin),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: text.label.copyWith(
                    color: isSelected ? tokens.textPrimary : tokens.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: FrameSpace.x1),
                // Selected state: an accent bar under the label.
                Container(
                  width: 24,
                  height: 2,
                  color: isSelected ? tokens.accent : tokens.surface.withValues(alpha: 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Spinner on the row of a session whose agent is at work. Static (a fixed
/// arc) under widget tests, so `pumpAndSettle` still settles; under reduced
/// motion [FrameActivityIndicator] shows a static glyph.
class _WorkingDot extends StatelessWidget {
  final Color color;

  const _WorkingDot({required this.color});

  static const double _size = 10.0;

  @override
  Widget build(BuildContext context) {
    // Phone browsers: one endless animation per working row made scrolling
    // the sessions drawer stutter, so they get the static arc too.
    final still = isWidgetTestBinding || (kIsWeb && MediaQuery.sizeOf(context).width < 700);
    return RepaintBoundary(
      child: FrameActivityIndicator(
        key: const ValueKey('session-working-spinner'),
        size: _size,
        strokeWidth: 1.6,
        value: still ? 0.7 : null,
        color: color,
      ),
    );
  }
}

/// Notification dot: dark while there is nothing new, lit while the session
/// has agent activity the user has not opened yet.
class _UnreadDot extends StatelessWidget {
  final bool unread;
  final double size;

  const _UnreadDot({super.key, required this.unread, this.size = 8.0});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AnimatedContainer(
      duration: FrameMotion.reduced(context) ? Duration.zero : FrameMotion.crossFade,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: unread ? tokens.accent : tokens.borderStrong.withValues(alpha: 0.45),
      ),
    );
  }
}

/// Divider between popup-menu groups, in the token border colour.
class _TokenMenuDivider extends PopupMenuEntry<String> {
  final Color color;

  const _TokenMenuDivider({required this.color});

  @override
  double get height => 1;

  @override
  bool represents(String? value) => false;

  @override
  State<_TokenMenuDivider> createState() => _TokenMenuDividerState();
}

class _TokenMenuDividerState extends State<_TokenMenuDivider> {
  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 1, color: widget.color);
  }
}

class _SessionTile extends ConsumerWidget {
  final Map<String, dynamic> session;
  final bool isPinned;
  final bool isPinnedSection;
  final bool isSelected;
  final bool isCursor;
  final VoidCallback onTap;
  final VoidCallback onPinToggle;
  final void Function(String id, String name) onRename;
  final void Function(String id) onTree;
  final void Function(String id) onClone;
  final void Function(String id, String name) onDelete;
  // The session name qualified by repository when names collide, from sessionDisplayNames.
  final String? qualifiedName;
  // Hands the rail the opener of this row's context menu (Shift+F10 on the cursor).
  final void Function(VoidCallback open)? onMenuOpener;

  /// Inset of a session under its repository row: 20 px, so it reads as a child.
  static const double _nestedIndent = 20;

  const _SessionTile({
    required this.session,
    required this.isPinned,
    required this.isPinnedSection,
    required this.isSelected,
    required this.isCursor,
    required this.onTap,
    required this.onPinToggle,
    required this.onRename,
    required this.onTree,
    required this.onClone,
    required this.onDelete,
    this.qualifiedName,
    this.onMenuOpener,
  });

  /// Session actions only. Repository actions live on the repository row.
  List<PopupMenuEntry<String>> _buildMenuItems(BuildContext context, FrameTokens tokens, AppStrings strings) {
    return [
      _menuAction(
        context,
        value: 'pin',
        icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin_outlined,
        iconColor: tokens.accent,
        label: isPinned ? strings.unpinAction : strings.pinAction,
        textColor: tokens.textPrimary,
      ),
      _menuAction(
        context,
        value: 'rename',
        icon: Icons.edit_outlined,
        iconColor: tokens.textSecondary,
        label: strings.renameAction,
        textColor: tokens.textPrimary,
      ),
      _menuAction(
        context,
        value: 'tree',
        icon: Icons.account_tree_outlined,
        iconColor: tokens.textSecondary,
        label: strings.branchTreeAction,
        textColor: tokens.textPrimary,
      ),
      _menuAction(
        context,
        value: 'clone',
        icon: Icons.copy_outlined,
        iconColor: tokens.textSecondary,
        label: strings.duplicateAction,
        textColor: tokens.textPrimary,
      ),
      _TokenMenuDivider(color: tokens.border),
      _menuAction(
        context,
        value: 'delete',
        icon: Icons.delete_outline,
        iconColor: tokens.danger,
        label: strings.deleteSessionAction,
        textColor: tokens.danger,
      ),
    ];
  }

  PopupMenuItem<String> _menuAction(
    BuildContext context, {
    required String value,
    required IconData icon,
    required Color iconColor,
    required String label,
    required Color textColor,
  }) {
    final text = FrameText.of(context);
    return PopupMenuItem(
      value: value,
      height: FrameSize.rowForm,
      padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: FrameSize.icon, color: iconColor),
          const SizedBox(width: FrameSpace.x2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.label.copyWith(color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  void _handleAction(String action, String id, String name) {
    switch (action) {
      case 'pin':
        onPinToggle();
      case 'rename':
        onRename(id, name);
      case 'tree':
        onTree(id);
      case 'clone':
        onClone(id);
      case 'delete':
        onDelete(id, name);
    }
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Rect anchor,
    FrameTokens tokens,
    AppStrings strings,
    String id,
    String name,
  ) async {
    final action = await showMenu<String>(
      context: context,
      color: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        side: BorderSide(color: tokens.border),
      ),
      position: menuPositionFor(context, anchor),
      items: _buildMenuItems(context, tokens, strings),
    );
    if (action != null) _handleAction(action, id, name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final id = session['id'] as String? ?? 's';
    // A chosen name (rename or Pi title); empty for a provisional one.
    final chosenName = _chosenNameOf(session);
    final prompt = ref.watch(sessionStateFamily(id).select(firstUserPrompt));
    final title = sessionRailTitle(
      id: id,
      name: session['name'] as String?,
      qualifiedName: qualifiedName,
      prompt: prompt,
      messageCount: (session['messageCount'] as num?)?.toInt(),
      lastPreview: session['lastMessagePreview'] as String?,
      listedPrompt: session['firstUserPrompt'] as String?,
      strings: strings,
    );
    final folder = _sessionFolder(session);
    final isStaticActive = session['isActive'] == true;

    // Sessions opened in this run stay subscribed, so their live state is
    // shown after switching away; the daemon listing lags a running turn.
    final unread = ref.read(unreadSessionsProvider.notifier);
    final isLive = isPinned || isSelected || isStaticActive || unread.isFollowed(id);
    if (isLive) unread.follow(id);
    final isWorking = isLive
        ? ref.watch(sessionStateFamily(id).select(agentAtWork)) ||
              // Waiting on background subagents or workflows still counts as running.
              ref.watch(backgroundAgentsRunningProvider(id))
        : (session['status'] == 'working' || session['isStreaming'] == true);
    final isUnread = !isSelected && ref.watch(unreadSessionsProvider.select((ids) => ids.contains(id)));

    final relative = relativeTimeLabel(strings, (session['lastActivityAt'] as num?)?.toInt());
    final metaColor = isSelected ? tokens.displayText.withValues(alpha: 0.8) : tokens.textMuted;

    final row = FrameListRow(
      key: ValueKey('session-row-$id'),
      name: title,
      secondary: relative,
      selected: isSelected,
      minHeight: _railRowMinHeight + (relative != null ? 8 : 0),
      leading: Center(
        child: isWorking
            ? _WorkingDot(color: tokens.agentWorking)
            : _UnreadDot(key: ValueKey('session-unread-dot-$id-$isUnread'), unread: isUnread),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [if (isPinned) Icon(Icons.push_pin_outlined, size: FrameSize.icon, color: tokens.accent)],
      ),
      actions: [
        PopupMenuButton<String>(
          key: ValueKey('session-menu-$id'),
          tooltip: strings.sessionActionsTooltip,
          icon: Icon(Icons.more_horiz_outlined, size: FrameSize.iconLg, color: metaColor),
          color: tokens.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            side: BorderSide(color: tokens.border),
          ),
          onSelected: (action) => _handleAction(action, id, chosenName),
          itemBuilder: (ctx) => _buildMenuItems(ctx, tokens, strings),
        ),
      ],
      onTap: onTap,
      onSecondaryTap: (position) =>
          _showContextMenu(context, pointerAnchorRect(position), tokens, strings, id, chosenName),
    );

    onMenuOpener?.call(() {
      if (!context.mounted) return;
      _showContextMenu(context, rowAnchorRect(context), tokens, strings, id, chosenName);
    });

    // The keyboard cursor and a working agent used the same colour (accent is
    // the focus ring colour), so a clicked card looked like a working one.
    // The cursor ring now shows only while navigating with the keyboard, and
    // a working card uses the agent-working colour.
    final borderColor = isCursor
        ? tokens.focusRing
        : (isWorking ? tokens.agentWorking.withValues(alpha: 0.7) : tokens.surface.withValues(alpha: 0));

    // Foreground: the selected and hovered row fills are opaque and hid a
    // border painted behind them.
    final content = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: row,
    );

    return Padding(
      key: ValueKey('session-tile-$folder-$id'),
      padding: EdgeInsets.only(
        left: isPinnedSection ? FrameSpace.x2 : _nestedIndent,
        right: FrameSpace.x1,
        bottom: FrameSpace.x1,
      ),
      child: content,
    );
  }
}
