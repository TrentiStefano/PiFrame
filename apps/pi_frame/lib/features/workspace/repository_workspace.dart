import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../domain/session/agent_status.dart';
import '../composer/composer_draft.dart';
import '../../data/terminal/terminal_settings.dart';
import 'integrated_terminal.dart';
import '../../ui/code/file_icon.dart';
import '../../ui/frame_snack_bar.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_workspace.dart';
import '../../data/language/strings_errors.dart';
import 'editor/repository_editor_pane.dart';
import 'repository_error_callout.dart';
import 'repository_state.dart';
import 'workspace_pane.dart';
import 'workspace_pane_header.dart';

export 'editor/repository_file_save.dart';
export 'git/git_changes_pane.dart';
export 'repository_state.dart';
export 'workspace_change_paths.dart';
export 'workspace_pane.dart';

final repoExpandedDirsProvider = StateProvider.family<Set<String>, String>(
  (ref, sessionId) => <String>{},
);



class RepositoryPane extends ConsumerStatefulWidget {
  const RepositoryPane({
    super.key,
    required this.sessionId,
    this.onCollapse,
    this.companionTabs,
    this.activeCompanionTab,
    this.onSelectCompanionTab,
  });
  final String sessionId;
  final VoidCallback? onCollapse;
  final List<WorkspacePane>? companionTabs;
  final WorkspacePane? activeCompanionTab;
  final ValueChanged<WorkspacePane>? onSelectCompanionTab;
  @override
  ConsumerState<RepositoryPane> createState() => _RepositoryPaneState();
}

class _RepositoryPaneState extends ConsumerState<RepositoryPane> {
  AppStrings _getStrings() => repositoryStrings(ref);

  // Keeps the editor state alive when the layout changes around it
  // (compact/wide switch, terminal open/close).
  final _editorKey = GlobalKey();

  final _searchController = TextEditingController();
  String _searchQuery = '';

  bool _terminalOpen = false;
  bool _terminalCollapsed = false;
  double _terminalHeight = 240.0;

  void _toggleTerminal() {
    setState(() {
      if (!_terminalOpen) {
        _terminalOpen = true;
        _terminalCollapsed = false;
      } else if (_terminalCollapsed) {
        _terminalCollapsed = false;
      } else {
        _terminalOpen = false;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(repositoryStateProvider(widget.sessionId).notifier)
            .loadFiles();
      }
    });
  }

  @override
  void didUpdateWidget(RepositoryPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _cachedRawFiles = null;
      _cachedTreeNodes = const [];
      _searchController.clear();
      _searchQuery = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(repositoryStateProvider(widget.sessionId).notifier)
              .loadFiles();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_TreeNode> _cachedTreeNodes = const [];
  Object? _cachedRawFiles;

  void _collapseAll() {
    ref.read(repoExpandedDirsProvider(widget.sessionId).notifier).state =
        <String>{};
  }

  void _expandAll(List<Map<String, dynamic>> raw) {
    final nodes = _getTreeNodes(raw);
    final allDirs = <String>{};
    _collectAllDirs(nodes, allDirs);
    ref.read(repoExpandedDirsProvider(widget.sessionId).notifier).state =
        allDirs;
  }

  List<_TreeNode> _getTreeNodes(List<Map<String, dynamic>> raw) {
    if (identical(raw, _cachedRawFiles)) return _cachedTreeNodes;
    _cachedRawFiles = raw;
    _cachedTreeNodes = _buildFileTree(raw);
    return _cachedTreeNodes;
  }

  List<_TreeNode> _filterTree(
    List<_TreeNode> nodes,
    String query,
    Set<String> matchingDirs,
  ) {
    final clean = query.toLowerCase();
    final result = <_TreeNode>[];
    for (final node in nodes) {
      if (node.isDirectory) {
        final subMatches = <String>{};
        final filteredChildren = _filterTree(node.children, query, subMatches);
        if (filteredChildren.isNotEmpty) {
          matchingDirs.add(node.path);
          matchingDirs.addAll(subMatches);
          result.add(
            _TreeNode(
              name: node.name,
              path: node.path,
              isDirectory: true,
              children: filteredChildren,
            ),
          );
        }
      } else {
        if (node.name.toLowerCase().contains(clean) ||
            node.path.toLowerCase().contains(clean)) {
          result.add(node);
        }
      }
    }
    return result;
  }

  Widget _fileList(
    FrameTokens tokens,
    RepositoryState repo,
    String? selectedPath, {
    required bool isCwdEmpty,
  }) {
    final isAttaching =
        (repo.error != null &&
            (repo.error!.contains('not found') ||
                repo.error!.contains('Session not found'))) ||
        (repo.files.isEmpty && isCwdEmpty);

    if (isAttaching || (repo.loading && repo.files.isEmpty)) {
      final strings = _getStrings();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tokens.accent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              strings.loadingFiles,
              style: TextStyle(color: tokens.textMuted, fontSize: 11),
            ),
          ],
        ),
      );
    }
    final strings = _getStrings();
    if (repo.files.isEmpty) {
      final error = repo.error;
      if (error == null) {
        return Center(
          child: Text(
            strings.noFilesAvailable,
            style: TextStyle(color: tokens.textMuted),
          ),
        );
      }
      return repositoryErrorCallout(strings, error, strings.filesLoadFailed);
    }

    final expandedDirs = ref.watch(repoExpandedDirsProvider(widget.sessionId));
    final rootNodes = _getTreeNodes(repo.files);
    final matchingDirs = <String>{};
    final displayNodes = _searchQuery.isEmpty
        ? rootNodes
        : _filterTree(rootNodes, _searchQuery, matchingDirs);

    final effectiveExpanded = _searchQuery.isEmpty
        ? expandedDirs
        : (Set<String>.from(expandedDirs)..addAll(matchingDirs));

    if (selectedPath != null && _searchQuery.isEmpty) {
      _expandParentsOf(selectedPath, effectiveExpanded);
    }
    final flatRows = _flattenTree(displayNodes, effectiveExpanded);

    return Column(
      children: [
        Container(
          height: 32,
          margin: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: tokens.background,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Icon(Icons.search, size: 14, color: tokens.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: strings.searchFilesHint,
                    hintStyle: TextStyle(color: tokens.textMuted, fontSize: 12),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  tooltip: strings.clearSearchTooltip,
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: flatRows.isEmpty && _searchQuery.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      strings.noFilesFound(_searchQuery),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: tokens.textMuted, fontSize: 12),
                    ),
                  ),
                )
              : ListView.builder(
                  key: PageStorageKey<String>(
                    'repository-files-${widget.sessionId}-$_searchQuery',
                  ),
                  itemCount: flatRows.length,
                  itemExtent: 28.0,
                  itemBuilder: (context, index) {
                    final row = flatRows[index];
                    final node = row.node;
                    final selected =
                        !node.isDirectory && node.path == selectedPath;
                    final isExpanded =
                        node.isDirectory &&
                        effectiveExpanded.contains(node.path);

                    return _TreeRow(
                      key: ValueKey(node.path),
                      row: row,
                      selected: selected,
                      isExpanded: isExpanded,
                      tokens: tokens,
                      onTap: () {
                        if (node.isDirectory) {
                          final currentExpanded = ref.read(
                            repoExpandedDirsProvider(widget.sessionId),
                          );
                          final next = Set<String>.from(currentExpanded);
                          if (next.contains(node.path)) {
                            next.remove(node.path);
                          } else {
                            next.add(node.path);
                          }
                          ref
                                  .read(
                                    repoExpandedDirsProvider(widget.sessionId)
                                        .notifier,
                                  )
                                  .state =
                              next;
                        } else {
                          ref
                              .read(
                                repositoryStateProvider(widget.sessionId)
                                    .notifier,
                              )
                              .selectFile(node.path);
                        }
                      },
                      onAddToChat: (filePath) {
                        appendFileMentionToComposer(
                          ref,
                          widget.sessionId,
                          filePath,
                        );
                        FrameSnackBar.show(
                          context,
                          message: strings.addedFileToChat(filePath),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final repo = ref.watch(repositoryStateProvider(widget.sessionId));
    final (readOnly, readOnlyReason, agentStatus, cwd) = ref.watch(
      sessionStateFamily(widget.sessionId)
          .select((s) => (s.readOnly, s.readOnlyReason, s.agentStatus, s.cwd)),
    );

    ref.listen<String>(
      sessionStateFamily(widget.sessionId).select((s) => s.cwd),
      (prev, next) {
        final currentRepo = ref.read(repositoryStateProvider(widget.sessionId));
        if (next.isNotEmpty &&
            (prev == null || prev.isEmpty || currentRepo.error != null)) {
          ref
              .read(repositoryStateProvider(widget.sessionId).notifier)
              .loadFiles();
        }
      },
    );

    ref.listen<RepositoryState>(repositoryStateProvider(widget.sessionId), (
      prev,
      next,
    ) {
      if (next.selectedPath != null &&
          next.selectedPath != prev?.selectedPath) {
        final currentExpanded = ref.read(
          repoExpandedDirsProvider(widget.sessionId),
        );
        final updated = Set<String>.from(currentExpanded);
        _expandParentsOf(next.selectedPath!, updated);
        if (updated.length != currentExpanded.length) {
          ref.read(repoExpandedDirsProvider(widget.sessionId).notifier).state =
              updated;
        }
      }
    });

    final path = repo.selectedPath;
    final writeBlocked =
        readOnly ||
        const {
          AgentStatus.working,
          AgentStatus.retrying,
          AgentStatus.compacting,
          AgentStatus.awaitingUser,
        }.contains(agentStatus);
    final strings = _getStrings();
    final blockReason = readOnly
        ? (readOnlyReason ?? strings.readOnlySessionCapital)
        : writeBlocked
        ? strings.savingDisabledReason(agentStatus.label)
        : null;
    return Container(
      decoration: BoxDecoration(color: tokens.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          workspacePaneHeader(
            context,
            'Repository',
            Icons.folder_outlined,
            companionTabs: widget.companionTabs,
            activeCompanionTab:
                widget.activeCompanionTab ?? WorkspacePane.repository,
            onSelectCompanionTab: widget.onSelectCompanionTab,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The integrated terminal spawns host processes and can only
                // run inside the desktop app.
                if (!kIsWeb)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    tooltip:
                        ref.watch(terminalSettingsProvider).mode ==
                            TerminalMode.native
                        ? strings.openNativeTerminalTooltip
                        : (_terminalOpen && !_terminalCollapsed
                              ? strings.hideTerminalTooltip
                              : strings.integratedTerminalTooltip),
                    onPressed: () {
                      final termSettings = ref.read(
                        terminalSettingsProvider,
                      );
                      if (termSettings.mode == TerminalMode.native) {
                        launchNativeTerminal(
                          cwd:
                              repo.rootPath ??
                              ref
                                  .read(
                                    sessionStateFamily(widget.sessionId),
                                  )
                                  .cwd,
                          nativeApp: termSettings.nativeApp,
                          customPath: termSettings.customPath,
                        );
                      } else {
                        _toggleTerminal();
                      }
                    },
                    icon: Icon(
                      _terminalOpen ? Icons.terminal : Icons.terminal_outlined,
                      size: 16,
                      color: _terminalOpen ? tokens.accent : null,
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: strings.collapseAllFoldersTooltip,
                  onPressed: _collapseAll,
                  icon: const Icon(Icons.unfold_less, size: 16),
                ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: strings.expandAllFoldersTooltip,
                  onPressed: () => _expandAll(repo.files),
                  icon: const Icon(Icons.unfold_more, size: 16),
                ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: strings.refreshFilesTooltip,
                  onPressed: repo.loading
                      ? null
                      : () => ref
                            .read(
                              repositoryStateProvider(widget.sessionId)
                                  .notifier,
                            )
                            .loadFiles(),
                  icon: const Icon(Icons.refresh, size: 16),
                ),
                if (widget.onCollapse != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    tooltip: strings.collapseRepoPanelTooltip,
                    onPressed: widget.onCollapse,
                    icon: const Icon(Icons.chevron_left, size: 18),
                  ),
                ],
              ],
            ),
          ),
          if (repo.rootPath != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                repo.rootPath!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 11,
                  fontFamily: tokens.monoFontFamily,
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final Widget upperContent;
                if (path == null) {
                  // No file opened: file tree occupies 100% of the pane width!
                  upperContent = _fileList(
                    tokens,
                    repo,
                    path,
                    isCwdEmpty: cwd.isEmpty,
                  );
                } else {
                  final compactFiles = constraints.maxWidth < 480;
                  if (compactFiles) {
                    upperContent = RepositoryEditorPane(
                      key: _editorKey,
                      sessionId: widget.sessionId,
                      compact: true,
                      readOnly: readOnly,
                      writeBlocked: writeBlocked,
                      blockReason: blockReason,
                    );
                  } else {
                    final treeWidth = (constraints.maxWidth * 0.28)
                        .clamp(180.0, 260.0)
                        .toDouble();
                    upperContent = Row(
                      children: [
                        SizedBox(
                          width: treeWidth,
                          child: _fileList(
                            tokens,
                            repo,
                            path,
                            isCwdEmpty: cwd.isEmpty,
                          ),
                        ),
                        VerticalDivider(width: 1, color: tokens.borderStrong),
                        Expanded(
                          child: RepositoryEditorPane(
                            key: _editorKey,
                            sessionId: widget.sessionId,
                            compact: false,
                            readOnly: readOnly,
                            writeBlocked: writeBlocked,
                            blockReason: blockReason,
                          ),
                        ),
                      ],
                    );
                  }
                }

                if (!_terminalOpen) {
                  return upperContent;
                }

                return Column(
                  children: [
                    Expanded(child: upperContent),
                    if (_terminalCollapsed)
                      _collapsedTerminalBar(tokens)
                    else ...[
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (details) {
                            final nextHeight =
                                _terminalHeight - details.delta.dy;
                            if (nextHeight < 60) {
                              setState(() => _terminalCollapsed = true);
                            } else {
                              setState(() {
                                _terminalHeight = nextHeight.clamp(
                                  100.0,
                                  (constraints.maxHeight * 0.85).clamp(
                                    120.0,
                                    1000.0,
                                  ),
                                );
                              });
                            }
                          },
                          child: Container(
                            height: 6,
                            color: tokens.border,
                            child: Center(
                              child: Container(
                                width: 32,
                                height: 2,
                                decoration: BoxDecoration(
                                  color: tokens.borderStrong,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: _terminalHeight.clamp(
                          100.0,
                          (constraints.maxHeight * 0.85).clamp(120.0, 1000.0),
                        ),
                        child: IntegratedTerminalPanel(
                          key: ValueKey(
                            'integrated_terminal_${widget.sessionId}',
                          ),
                          cwd: repo.rootPath ?? cwd,
                          tokens: tokens,
                          onCollapseDownward: () =>
                              setState(() => _terminalCollapsed = true),
                          onClose: () => setState(() => _terminalOpen = false),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          if (repo.truncated)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                strings.fileListLimitedNotice,
                style: TextStyle(color: tokens.textMuted, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _collapsedTerminalBar(FrameTokens tokens) {
    final strings = _getStrings();
    return InkWell(
      onTap: () => setState(() => _terminalCollapsed = false),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border(top: BorderSide(color: tokens.borderStrong)),
        ),
        child: Row(
          children: [
            Icon(Icons.keyboard_arrow_up, size: 16, color: tokens.accent),
            const SizedBox(width: 6),
            Icon(Icons.terminal, size: 13, color: tokens.displayText),
            const SizedBox(width: 6),
            Text(
              strings.terminalBadge,
              style: TextStyle(
                color: tokens.displayText,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              tooltip: strings.expandTerminalTooltip,
              icon: const Icon(Icons.unfold_more, size: 14),
              onPressed: () => setState(() => _terminalCollapsed = false),
            ),
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              tooltip: strings.closeTerminalTooltip,
              icon: const Icon(Icons.close, size: 13),
              onPressed: () => setState(() => _terminalOpen = false),
            ),
          ],
        ),
      ),
    );
  }
}


class _TreeNode {
  final String name;
  final String path;
  final bool isDirectory;
  final List<_TreeNode> children;

  const _TreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.children = const [],
  });
}

class _TreeDirBuilder {
  final String name;
  final String path;
  final Map<String, _TreeDirBuilder> dirs = {};
  final List<_TreeNode> files = [];

  _TreeDirBuilder(this.name, this.path);

  List<_TreeNode> toChildren() {
    final sortedDirs = dirs.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final sortedFiles = List<_TreeNode>.of(files)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return [
      for (final d in sortedDirs)
        _TreeNode(
          name: d.name,
          path: d.path,
          isDirectory: true,
          children: d.toChildren(),
        ),
      ...sortedFiles,
    ];
  }
}

List<_TreeNode> _buildFileTree(List<Map<String, dynamic>> raw) {
  final root = _TreeDirBuilder('', '');
  for (final item in raw) {
    final rawPath = item['path']?.toString();
    if (rawPath == null || rawPath.isEmpty) continue;
    final normalized = rawPath.replaceAll('\\', '/');
    final cleanPath = normalized.replaceFirst(RegExp(r'^\.?/'), '');
    final segments = cleanPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) continue;

    var curr = root;
    var accumulated = '';
    for (var i = 0; i < segments.length - 1; i++) {
      final seg = segments[i];
      accumulated = accumulated.isEmpty ? seg : '$accumulated/$seg';
      curr = curr.dirs.putIfAbsent(
        seg,
        () => _TreeDirBuilder(seg, accumulated),
      );
    }
    final fileName = segments.last;
    curr.files.add(
      _TreeNode(name: fileName, path: cleanPath, isDirectory: false),
    );
  }
  return root.toChildren();
}

class _FlatTreeRow {
  final _TreeNode node;
  final int depth;
  const _FlatTreeRow({required this.node, required this.depth});
}

List<_FlatTreeRow> _flattenTree(
  List<_TreeNode> nodes,
  Set<String> expandedDirs,
) {
  final result = <_FlatTreeRow>[];
  void walk(List<_TreeNode> list, int depth) {
    for (final node in list) {
      result.add(_FlatTreeRow(node: node, depth: depth));
      if (node.isDirectory && expandedDirs.contains(node.path)) {
        walk(node.children, depth + 1);
      }
    }
  }

  walk(nodes, 0);
  return result;
}

void _collectAllDirs(List<_TreeNode> nodes, Set<String> target) {
  for (final node in nodes) {
    if (node.isDirectory) {
      target.add(node.path);
      _collectAllDirs(node.children, target);
    }
  }
}

void _expandParentsOf(String path, Set<String> target) {
  final normalized = path
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^\.?/'), '');
  final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
  var accumulated = '';
  for (var i = 0; i < segments.length - 1; i++) {
    accumulated = accumulated.isEmpty
        ? segments[i]
        : '$accumulated/${segments[i]}';
    target.add(accumulated);
  }
}

class _TreeRow extends ConsumerWidget {
  const _TreeRow({
    super.key,
    required this.row,
    required this.selected,
    required this.isExpanded,
    required this.tokens,
    required this.onTap,
    this.onAddToChat,
  });

  final _FlatTreeRow row;
  final bool selected;
  final bool isExpanded;
  final FrameTokens tokens;
  final VoidCallback onTap;
  final ValueChanged<String>? onAddToChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppStrings strings;
    try {
      strings = ref.watch(appStringsProvider);
    } catch (_) {
      strings = const AppStrings(AppLanguage.it);
    }
    final node = row.node;
    final indent = (row.depth * 14.0).clamp(0.0, 160.0);

    return RepaintBoundary(
      child: Tooltip(
        message: node.path,
        waitDuration: const Duration(milliseconds: 700),
        child: Material(
          color: selected
              ? tokens.surfaceElevated
              : tokens.surface.withValues(alpha: 0),
          child: GestureDetector(
            onSecondaryTapDown: (details) {
              if (!node.isDirectory && onAddToChat != null) {
                final pos = details.globalPosition;
                showMenu<String>(
                  context: context,
                  position: RelativeRect.fromLTRB(
                    pos.dx,
                    pos.dy,
                    pos.dx + 1,
                    pos.dy + 1,
                  ),
                  items: [
                    PopupMenuItem(
                      value: 'chat',
                      child: Row(
                        children: [
                          Icon(
                            Icons.add_comment_outlined,
                            size: 16,
                            color: tokens.accent,
                          ),
                          const SizedBox(width: 8),
                          Text(strings.addPathToChat),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: [
                          Icon(Icons.copy, size: 16, color: tokens.textMuted),
                          const SizedBox(width: 8),
                          Text(strings.copyPath),
                        ],
                      ),
                    ),
                  ],
                ).then((choice) {
                  if (choice == 'chat') {
                    onAddToChat!(node.path);
                  } else if (choice == 'copy') {
                    Clipboard.setData(ClipboardData(text: node.path));
                    if (context.mounted) {
                      FrameSnackBar.show(
                        context,
                        message: strings.pathCopied(node.path),
                      );
                    }
                  }
                });
              }
            },
            child: InkWell(
              onTap: onTap,
              hoverColor: tokens.accent.withValues(alpha: 0.08),
              child: SizedBox(
                height: 28.0,
                child: Padding(
                  padding: EdgeInsets.only(left: 4.0 + indent, right: 8.0),
                  child: Row(
                    children: [
                      if (node.isDirectory) ...[
                        Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 14,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(width: 4),
                        FileIcon(
                          path: node.path,
                          isDirectory: true,
                          isExpanded: isExpanded,
                          size: 15,
                        ),
                      ] else ...[
                        const SizedBox(width: 14),
                        const SizedBox(width: 4),
                        FileIcon(path: node.path, size: 15),
                      ],
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          node.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? tokens.accent
                                : (node.isDirectory
                                      ? tokens.textPrimary
                                      : tokens.textSecondary),
                            fontSize: 12,
                            fontFamily: tokens.uiFontFamily,
                            fontWeight: selected || node.isDirectory
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (!node.isDirectory && onAddToChat != null)
                        IconButton(
                          tooltip: strings.addPathToChat,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          icon: Icon(
                            Icons.add_comment_outlined,
                            size: 14,
                            color: selected ? tokens.accent : tokens.textMuted,
                          ),
                          onPressed: () => onAddToChat!(node.path),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkspaceFileEntry {
  final String path;
  final String fileName;
  final String? parentDir;
  final int depth;

  const WorkspaceFileEntry({
    required this.path,
    required this.fileName,
    this.parentDir,
    this.depth = 0,
  });

  factory WorkspaceFileEntry.fromMap(Map<String, dynamic> map) {
    final filePath = map['path'].toString();
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash == -1) {
      return WorkspaceFileEntry(path: filePath, fileName: filePath, depth: 0);
    }
    final parent = filePath.substring(0, lastSlash);
    final name = filePath.substring(lastSlash + 1);
    final slashCount = '/'.allMatches(parent).length;
    return WorkspaceFileEntry(
      path: filePath,
      fileName: name,
      parentDir: parent,
      depth: slashCount + 1,
    );
  }
}
