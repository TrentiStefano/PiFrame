import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'instruction_file_dialog.dart';
import 'session_actions.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/shimmer_border.dart';
import '../command_palette/command_palette.dart';
import '../session_tree/session_tree_dialog.dart';
import '../transcript/workflows_provider.dart';
import '../workspace/repository_workspace.dart';
import 'pinned_sessions_provider.dart';
import 'removed_repos_provider.dart';
import '../../domain/session/agent_status.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_shell.dart';
import '../../data/update/update_providers.dart';

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

String _sessionFolder(Map<String, dynamic> session) {
  final gitRoot = (session['gitRoot'] ?? '').toString().trim();
  return gitRoot.isNotEmpty ? gitRoot : (session['cwd'] ?? '').toString();
}

String _folderName(String path, [String fallback = 'Sessioni']) {
  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty);
  return segments.isEmpty ? fallback : segments.last;
}

class SessionsSidebar extends ConsumerStatefulWidget {
  final VoidCallback? onSessionSelected;
  final VoidCallback? onCollapse;

  const SessionsSidebar({
    super.key,
    this.onSessionSelected,
    this.onCollapse,
  });

  @override
  ConsumerState<SessionsSidebar> createState() => _SessionsSidebarState();
}

class _SessionsSidebarState extends ConsumerState<SessionsSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterMode = 'all'; // 'all', 'active', 'repo'
  bool _creating = false;
  final Set<String> _expandedFolders = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: textController,
            autofocus: true,
            style: TextStyle(color: tokens.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: strings.sessionNameHint,
              hintStyle: TextStyle(color: tokens.textMuted, fontSize: 13),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.surface,
              ),
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
            FrameSnackBar.show(
              context,
              message: strings.sessionRenamedNotice(newName),
            );
          }
        } catch (e) {
          if (mounted) {
            FrameSnackBar.show(
              context,
              message: strings.renameErrorNotice(e),
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
    if (!await resolveDirtyRepository(
      context,
      ref,
      ref.read(activeSessionIdProvider),
    )) {
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
          FrameSnackBar.show(
            context,
            message: strings.sessionDuplicatedNotice(newSid),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: strings.duplicateErrorNotice(e),
          backgroundColor: tokens.danger,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final sessionsAsync = ref.watch(sessionListProvider);
    final activeId = ref.watch(activeSessionIdProvider);
    final activeSessionCwd = activeId != null
        ? ref.watch(sessionStateFamily(activeId).select((s) => s.cwd))
        : '';

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: tokens.surface,
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: tokens.border, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    strings.sidebarTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 18,
                      height: 1.1,
                      fontFamily: tokens.headingFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh, color: tokens.textMuted, size: 18),
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
                  icon: Icon(Icons.add, color: tokens.accent, size: 20),
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
                    icon: Icon(Icons.chevron_left, color: tokens.textMuted, size: 20),
                    tooltip: strings.collapseSidebarTooltip,
                    onPressed: widget.onCollapse,
                  ),
              ],
            ),
          ),

          // Search Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: tokens.border, width: 1),
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: tokens.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: strings.searchSessionsHint,
                hintStyle: TextStyle(color: tokens.textMuted, fontSize: 12),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: tokens.textMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          size: 14,
                          color: tokens.textMuted,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: tokens.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
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

          // Filter Chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: tokens.border, width: 1),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', strings.filterAll, tokens),
                  const SizedBox(width: 6),
                  _buildFilterChip('active', strings.filterActive, tokens),
                  const SizedBox(width: 6),
                  _buildFilterChip('repo', strings.filterRepo, tokens),
                ],
              ),
            ),
          ),

          // Session list
          Expanded(
            child: sessionsAsync.when(
              data: (allSessions) {
                final removedRepos = ref.watch(removedReposProvider);

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
                  final preview = (s['lastMessagePreview'] as String? ?? '')
                      .toLowerCase();
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
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _searchQuery.isNotEmpty || _filterMode != 'all'
                            ? strings.noSessionsMatchFilters
                            : strings.noSessionsFound,
                        style: TextStyle(color: tokens.textMuted, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final pinnedIds = ref.watch(pinnedSessionsProvider);
                final sessionMap = {
                  for (final s in allSessions)
                    if (s['id'] is String) s['id'] as String: s
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
                  grouped
                      .putIfAbsent(_sessionFolder(session), () => [])
                      .add(session);
                }
                final folderRows =
                    <({String? folder, Map<String, dynamic>? session, bool isFolder})>[];

                for (final group in grouped.entries) {
                  folderRows.add((folder: group.key, session: null, isFolder: true));
                  final isExpanded = _expandedFolders.contains(group.key) ||
                      _searchQuery.isNotEmpty;
                  if (isExpanded) {
                    folderRows.addAll(
                      group.value.map(
                        (session) => (folder: null, session: session, isFolder: false),
                      ),
                    );
                  }
                }

                final showPinnedSection = _searchQuery.isEmpty &&
                    _filterMode == 'all' &&
                    pinnedSessions.isNotEmpty;

                Widget buildPinnedHeader() {
                  final hasWorkingPinned = pinnedSessions.any((s) {
                    final sId = s['id'] as String? ?? '';
                    return ref.watch(sessionStateFamily(sId).select((st) =>
                        st.agentStatus == AgentStatus.working ||
                        st.isStreaming ||
                        st.activeToolCalls.isNotEmpty));
                  });
                  final hasActivePinned = hasWorkingPinned ||
                      pinnedSessions.any((s) => s['isActive'] == true);

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: Row(
                      children: [
                        Icon(Icons.push_pin, size: 13, color: tokens.accent),
                        const SizedBox(width: 6),
                        Text(
                          strings.pinnedSessionsHeader(pinnedSessions.length),
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (hasWorkingPinned) ...[
                          const SizedBox(width: 6),
                          _WorkingDot(color: tokens.agentWorking, size: 7),
                        ] else if (hasActivePinned) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tokens.accent,
                              boxShadow: [
                                BoxShadow(
                                  color: tokens.accent.withValues(alpha: 0.6),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return CustomScrollView(
                  slivers: [
                    if (showPinnedSection) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                        sliver: SliverToBoxAdapter(
                          child: buildPinnedHeader(),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        sliver: SliverReorderableList(
                          itemCount: pinnedSessions.length,
                          proxyDecorator: (child, index, animation) {
                            return Material(
                              elevation: 4,
                              color: tokens.surfaceElevated,
                              borderRadius:
                                  BorderRadius.circular(tokens.radiusSm),
                              child: child,
                            );
                          },
                          onReorderItem: (oldIndex, newIndex) {
                            if (oldIndex < 0 ||
                                oldIndex >= pinnedSessions.length) {
                              return;
                            }
                            final movedId =
                                pinnedSessions[oldIndex]['id'] as String? ?? '';
                            if (movedId.isEmpty) {
                              return;
                            }
                            ref
                                .read(pinnedSessionsProvider.notifier)
                                .reorderById(movedId, newIndex);
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
                                isPinnedSection: true,
                                isSelected: isSelected,
                                onTap: () async {
                                  if (await switchSessionSafely(
                                      context, ref, id)) {
                                    widget.onSessionSelected?.call();
                                  }
                                },
                                onPinToggle: () => ref
                                    .read(pinnedSessionsProvider.notifier)
                                    .togglePin(id),
                                onRename: (sId, sName) =>
                                    _showRenameDialog(sId, sName),
                                onTree: (sId) => SessionTreeDialog.show(
                                  context,
                                  sessionId: sId,
                                ),
                                onClone: (sId) => _cloneSession(sId),
                                onInstructions: (sId, folder) =>
                                    InstructionFileDialog.show(
                                  context,
                                  folder: folder,
                                  sessionId: sId,
                                ),
                                onRemoveRepo: (folder) =>
                                    removeRepoWithConfirmation(
                                  context,
                                  ref,
                                  folder: folder,
                                  repoName: _folderName(folder),
                                  folderSessions: grouped[folder] ?? [s],
                                ),
                                onDelete: (sId, sName) =>
                                    deleteSessionWithConfirmation(
                                  context,
                                  ref,
                                  sessionId: sId,
                                  sessionName: sName,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (rowContext, index) {
                            final row = folderRows[index];
                            if (row.isFolder) {
                      final folder = row.folder ?? '';
                      final expanded = _expandedFolders.contains(folder);
                      final hasActive = activeFolders.contains(folder);
                      final folderSessions = grouped[folder] ?? [];
                      final hasWorking = folderSessions.any((s) {
                        final sId = s['id'] as String? ?? '';
                        final isSel = sId == activeId;
                        final isPin = pinnedIds.contains(sId);
                        final isAct = s['isActive'] == true;
                        if (isSel || isPin || isAct) {
                          final isWorking = ref.watch(sessionStateFamily(sId).select((st) =>
                              st.agentStatus == AgentStatus.working ||
                              st.agentStatus == AgentStatus.retrying ||
                              st.agentStatus == AgentStatus.compacting ||
                              st.isStreaming ||
                              st.activeToolCalls.isNotEmpty)) ||
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              expanded
                                  ? Icons.folder_open_outlined
                                  : Icons.folder_outlined,
                              size: 16,
                              color: hasWorking
                                  ? tokens.agentWorking
                                  : (hasActive
                                      ? tokens.accent
                                      : tokens.accent.withValues(alpha: 0.8)),
                            ),
                            if (hasWorking) ...[
                              const SizedBox(width: 4),
                              Container(
                                key: ValueKey('folder-working-dot:$folder'),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tokens.agentWorking,
                                ),
                              ),
                            ] else if (hasActive) ...[
                              const SizedBox(width: 4),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tokens.accent,
                                ),
                              ),
                            ],
                          ],
                        ),
                        title: Text(
                          _folderName(folder, strings.sidebarFallbackFolderLabel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        subtitle: Text(
                          folder.isEmpty ? strings.unknownFolderLabel : folder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('repo-new-session-btn-$folder'),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                minimumSize: const Size(20, 20),
                                padding: EdgeInsets.zero,
                              ),
                              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                              icon: Icon(Icons.add, size: 14, color: tokens.accent),
                              tooltip: strings.newSessionInFolderTooltip,
                              onPressed: () async {
                                setState(() => _expandedFolders.add(folder));
                                await createSession(context, ref, cwd: folder);
                                if (mounted) widget.onSessionSelected?.call();
                              },
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              expanded ? Icons.expand_more : Icons.chevron_right,
                              size: 16,
                              color: tokens.textMuted,
                            ),
                          ],
                        ),
                        onTap: () => setState(() {
                          if (expanded) {
                            _expandedFolders.remove(folder);
                          } else {
                            _expandedFolders.add(folder);
                          }
                        }),
                      );

                      folderTile = GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapDown: (details) async {
                          final pos = details.globalPosition;
                          final action = await showMenu<String>(
                            context: context,
                            color: tokens.surfaceElevated,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(tokens.radiusSm),
                              side: BorderSide(color: tokens.border),
                            ),
                            position: RelativeRect.fromLTRB(
                              pos.dx,
                              pos.dy,
                              pos.dx + 1,
                              pos.dy + 1,
                            ),
                            items: [
                              PopupMenuItem(
                                value: 'instructions',
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.description_outlined,
                                      size: 14,
                                      color: tokens.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        strings.repoInstructionsAction,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: tokens.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'new_session',
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add,
                                      size: 14,
                                      color: tokens.accent,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        strings.newSessionAction,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: tokens.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              PopupMenuItem(
                                value: 'remove_repo',
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.close,
                                      size: 14,
                                      color: tokens.danger,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        strings.removeRepoFromSidebarAction,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: tokens.danger,
                                          fontSize: 12,
                                        ),
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
                            setState(() => _expandedFolders.add(folder));
                            await createSession(context, ref, cwd: folder);
                            if (mounted) widget.onSessionSelected?.call();
                          } else if (action == 'remove_repo') {
                            removeRepoWithConfirmation(
                              context,
                              ref,
                              folder: folder,
                              repoName: _folderName(folder),
                              folderSessions: folderSessions,
                            );
                          }
                        },
                        child: folderTile,
                      );

                      return Material(
                        color: tokens.surface,
                        child: folderTile,
                      );
                    }

                    final s = row.session!;
                    final id = s['id'] as String? ?? 's';
                    final isSelected = id == activeId;
                    final isPinned = pinnedIds.contains(id);

                    return _SessionTile(
                        session: s,
                        isPinned: isPinned,
                        isPinnedSection: false,
                        isSelected: isSelected,
                        onTap: () async {
                          if (await switchSessionSafely(context, ref, id)) {
                            widget.onSessionSelected?.call();
                          }
                        },
                        onPinToggle: () => ref
                            .read(pinnedSessionsProvider.notifier)
                            .togglePin(id),
                        onRename: (sId, sName) => _showRenameDialog(sId, sName),
                        onTree: (sId) =>
                            SessionTreeDialog.show(context, sessionId: sId),
                        onClone: (sId) => _cloneSession(sId),
                        onInstructions: (sId, folder) => InstructionFileDialog.show(
                          context,
                          folder: folder,
                          sessionId: sId,
                        ),
                        onRemoveRepo: (folder) => removeRepoWithConfirmation(
                          context,
                          ref,
                          folder: folder,
                          repoName: _folderName(folder),
                          folderSessions: grouped[folder] ?? [s],
                        ),
                        onDelete: (sId, sName) => deleteSessionWithConfirmation(
                          context,
                          ref,
                          sessionId: sId,
                          sessionName: sName,
                        ),
                      );
                    },
                    childCount: folderRows.length,
                  ),
                ),
              ),
            ],
          );
              },
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: tokens.accent,
                  strokeWidth: 2,
                ),
              ),
              error: (err, _) => Center(
                child: Text(
                  strings.sidebarErrorNotice(err),
                  style: TextStyle(color: tokens.danger, fontSize: 12),
                ),
              ),
            ),
          ),

          // Bottom utility bar: Command Palette & Settings
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.border, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      alignment: Alignment.centerLeft,
                    ),
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.settings_outlined, size: 16),
                        if (ref.watch(hasUpdateBadgeProvider))
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: tokens.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    label: Text(
                      strings.settingsLabel,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      ref.read(showSettingsProvider.notifier).state = true;
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.search, size: 16, color: tokens.textMuted),
                  tooltip: strings.commandPaletteTooltip,
                  onPressed: () {
                    CommandPalette.show(
                      context,
                      onOpenSettings: () {
                        ref.read(showSettingsProvider.notifier).state = true;
                      },
                    );
                  },
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
    return Semantics(
      selected: isSelected,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: isSelected ? tokens.displayText : tokens.textPrimary,
          backgroundColor: isSelected
              ? tokens.surfaceElevated
              : tokens.surface.withValues(alpha: 0),
          side: BorderSide(
            color: isSelected ? tokens.focusRing : tokens.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          textStyle: TextStyle(
            fontSize: 11,
            fontFamily: tokens.uiFontFamily,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        onPressed: () => setState(() => _filterMode = mode),
        child: Text(label),
      ),
    );
  }
}

class _WorkingDot extends StatefulWidget {
  final Color color;
  final double size;

  const _WorkingDot({
    required this.color,
    this.size = 8.0,
  });

  @override
  State<_WorkingDot> createState() => _WorkingDotState();
}

class _WorkingDotState extends State<_WorkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    final isTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (!isTest) {
      _controller.repeat(reverse: true);
    }
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = _controller.isAnimating ? _pulse.value : 1.0;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.75 + 0.25 * scale),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.65 * scale),
                blurRadius: 5.0 * scale,
                spreadRadius: 1.2 * scale,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SessionTile extends ConsumerWidget {
  final Map<String, dynamic> session;
  final bool isPinned;
  final bool isPinnedSection;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onPinToggle;
  final void Function(String id, String name) onRename;
  final void Function(String id) onTree;
  final void Function(String id) onClone;
  final void Function(String id, String folder)? onInstructions;
  final void Function(String folder)? onRemoveRepo;
  final void Function(String id, String name)? onDelete;

  const _SessionTile({
    required this.session,
    required this.isPinned,
    required this.isPinnedSection,
    required this.isSelected,
    required this.onTap,
    required this.onPinToggle,
    required this.onRename,
    required this.onTree,
    required this.onClone,
    this.onInstructions,
    this.onRemoveRepo,
    this.onDelete,
  });

  List<PopupMenuEntry<String>> _buildMenuItems(
    BuildContext context,
    FrameTokens tokens,
    AppStrings strings,
  ) {
    return [
      PopupMenuItem(
        value: 'pin',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              size: 14,
              color: tokens.accent,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isPinned ? strings.unpinAction : strings.pinAction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'instructions',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 14,
              color: tokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                strings.repoInstructionsAction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'rename',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_outlined,
              size: 14,
              color: tokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                strings.renameAction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'tree',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 14,
              color: tokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                strings.branchTreeAction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'clone',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.copy_outlined,
              size: 14,
              color: tokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                strings.duplicateAction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(height: 1),
      if (onRemoveRepo != null) ...[
        PopupMenuItem(
          value: 'remove_repo',
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.close,
                size: 14,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  strings.removeRepoFromSidebarAction,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      PopupMenuItem(
        value: 'delete',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              size: 14,
              color: tokens.danger,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                strings.deleteSessionAction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.danger,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  void _handleAction(
    String action,
    String id,
    String name,
    String folder,
  ) {
    if (action == 'pin') {
      onPinToggle();
    } else if (action == 'instructions') {
      onInstructions?.call(id, folder);
    } else if (action == 'rename') {
      onRename(id, name);
    } else if (action == 'tree') {
      onTree(id);
    } else if (action == 'clone') {
      onClone(id);
    } else if (action == 'remove_repo') {
      onRemoveRepo?.call(folder);
    } else if (action == 'delete') {
      onDelete?.call(id, name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final id = session['id'] as String? ?? 's';
    final name = session['name'] as String? ?? id;
    final cwd = session['cwd'] as String? ?? '';
    final preview = session['lastMessagePreview'] as String?;
    final isStaticActive = session['isActive'] == true;
    final folder = _sessionFolder(session);

    final isWorking = (isPinned || isSelected || isStaticActive)
        ? ref.watch(sessionStateFamily(id).select((s) =>
            s.agentStatus == AgentStatus.working ||
            s.agentStatus == AgentStatus.retrying ||
            s.agentStatus == AgentStatus.compacting ||
            s.isStreaming ||
            s.activeToolCalls.isNotEmpty)) ||
            // Waiting on background subagents or workflows still counts as running.
            ref.watch(backgroundAgentsRunningProvider(id))
        : (session['status'] == 'working' || session['isStreaming'] == true);

    final tile = ListTile(
      selected: isSelected,
      selectedColor: tokens.displayText,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 2,
      minLeadingWidth: 14,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 0,
      ),
      leading: isWorking
          ? _WorkingDot(color: tokens.agentWorking)
          : Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? tokens.displayText
                    : (isStaticActive
                        ? tokens.agentSettled
                        : tokens.textMuted.withValues(
                            alpha: 0.5,
                          )),
                border: Border.all(color: tokens.borderStrong),
              ),
            ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? tokens.displayText : tokens.textPrimary,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (isPinned) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.push_pin,
              size: 11,
              color: tokens.accent,
            ),
          ],
        ],
      ),
      subtitle: Text(
        preview != null && preview.isNotEmpty ? preview : cwd,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isSelected
              ? tokens.displayText.withValues(alpha: 0.8)
              : tokens.textMuted,
          fontSize: 12,
        ),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: strings.sessionActionsTooltip,
        icon: Icon(
          Icons.more_horiz,
          size: 18,
          color: isSelected ? tokens.displayText : tokens.textMuted,
        ),
        color: tokens.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          side: BorderSide(color: tokens.border),
        ),
        onSelected: (action) => _handleAction(action, id, name, folder),
        itemBuilder: (ctx) => _buildMenuItems(ctx, tokens, strings),
      ),
      onTap: onTap,
    );

    final card = Material(
      color: isSelected
          ? tokens.displaySurface
          : tokens.surfaceElevated.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        side: BorderSide(
          color: isSelected ? tokens.focusRing : tokens.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: tile,
    );

    final interactiveCard = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) async {
        final pos = details.globalPosition;
        final action = await showMenu<String>(
          context: context,
          color: tokens.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            side: BorderSide(color: tokens.border),
          ),
          position: RelativeRect.fromLTRB(
            pos.dx,
            pos.dy,
            pos.dx + 1,
            pos.dy + 1,
          ),
          items: _buildMenuItems(context, tokens, strings),
        );
        if (action != null) {
          _handleAction(action, id, name, folder);
        }
      },
      child: card,
    );

    if (isWorking) {
      return Padding(
        padding: EdgeInsets.only(
          left: isPinnedSection ? 4 : 14,
          right: 4,
          bottom: 3,
        ),
        child: ShimmerBorder(
          isActive: true,
          strokeWidth: 1.0,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          child: interactiveCard,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: isPinnedSection ? 4 : 14,
        right: 4,
        bottom: 3,
      ),
      child: interactiveCard,
    );
  }
}


