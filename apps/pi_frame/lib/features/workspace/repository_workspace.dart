import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../domain/errors/user_facing_error.dart';
import '../../domain/session/agent_status.dart';
import '../composer/composer_draft.dart';
import '../../ui/code/code_editor_controller.dart';
import '../../data/terminal/terminal_settings.dart';
import 'integrated_terminal.dart';
import '../../ui/code/file_icon.dart';
import '../transcript/rich_content.dart';
import '../../ui/frame_error_callout.dart';
import '../../ui/frame_snack_bar.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_workspace.dart';
import '../../data/language/strings_errors.dart';
import 'repository_state.dart';
import 'workspace_pane.dart';
import 'workspace_pane_header.dart';

export 'git/git_changes_pane.dart';
export 'repository_state.dart';
export 'workspace_change_paths.dart';
export 'workspace_pane.dart';

final repoExpandedDirsProvider = StateProvider.family<Set<String>, String>(
  (ref, sessionId) => <String>{},
);


Future<bool> switchSessionSafely(
  BuildContext context,
  WidgetRef ref,
  String nextId,
) async {
  final currentId = ref.read(activeSessionIdProvider);
  if (currentId == nextId) return true;
  if (!context.mounted) return false;
  if (!await resolveDirtyRepository(context, ref, currentId)) return false;
  if (!context.mounted) return false;
  ref.read(activeSessionIdProvider.notifier).state = nextId;
  return true;
}

Future<bool> resolveDirtyRepository(
  BuildContext context,
  WidgetRef ref,
  String? sessionId,
) async {
  if (sessionId == null) return true;
  final controller = ref.read(repositoryStateProvider(sessionId).notifier);
  if (!controller.currentState.dirty) return true;
  final tokens = context.tokens;
  final session = ref.read(sessionStateFamily(sessionId));
  final strings = ref.read(appStringsProvider);
  final writesBlocked = sessionWritesBlocked(session);
  final canSave = !writesBlocked && ref.read(pcpClientProvider) != null;
  final blockedReason = session.readOnly
      ? (session.readOnlyReason ?? strings.readOnlySessionLower)
      : writesBlocked
      ? session.agentStatus.label
      : strings.daemonNotConnectedLower;
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: tokens.surface,
      title: Text(strings.unsavedChangesTitle),
      content: Text(
        canSave
            ? strings.unsavedChangesContentCanSave
            : strings.unsavedChangesContentBlocked(blockedReason),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'cancel'),
          child: Text(strings.cancel),
        ),
        if (canSave)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: Text(strings.discard),
          ),
        if (!canSave)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: Text(strings.discard),
          ),
        if (canSave)
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: Text(strings.save),
          ),
      ],
    ),
  );
  if (!context.mounted) return false;
  if (choice == 'discard') {
    controller.discardDirty();
    return true;
  }
  if (choice != 'save') return false;
  try {
    for (final entry
        in controller.currentState.buffers.entries
            .where((entry) => entry.value.dirty)
            .toList()) {
      await saveRepositoryFile(context, ref, sessionId, entry.key);
      if (!context.mounted ||
          controller.currentState.buffers[entry.key]?.dirty == true) {
        return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> saveRepositoryFile(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
  String path,
) async {
  final session = ref.read(sessionStateFamily(sessionId));
  final strings = ref.read(appStringsProvider);
  if (sessionWritesBlocked(session)) {
    throw StateError(
      session.readOnly
          ? (session.readOnlyReason ?? strings.readOnlySessionCapital)
          : session.agentStatus.label,
    );
  }
  final controller = ref.read(repositoryStateProvider(sessionId).notifier);
  try {
    await controller.save(path);
  } catch (error) {
    final message = error.toString().toLowerCase();
    if (!message.contains('conflict') &&
        !message.contains('changed on disk') &&
        !message.contains('reload before saving')) {
      rethrow;
    }
    final disk = await controller.currentDisk(path);
    if (!context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.fileModifiedExternallyTitle),
        content: Text(
          strings.fileModifiedExternallyContent(path),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'keep'),
            child: Text(strings.keepChanges),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'reload'),
            child: Text(strings.reloadFromDisk),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'overwrite'),
            child: Text(strings.overwriteExplicitly),
          ),
        ],
      ),
    );
    if (choice == 'reload') {
      controller.reload(path, disk.content, disk.revision);
    }
    if (choice == 'overwrite') {
      await controller.save(path, revisionOverride: disk.revision);
    }
    if (choice == 'keep') rethrow;
  }
}

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
  AppStrings _getStrings() {
    try {
      return ref.watch(appStringsProvider);
    } catch (_) {
      return const AppStrings(AppLanguage.it);
    }
  }

  CodeEditorController? _editor;
  String? _editorPath;
  bool _previewMarkdown = true;
  final _markdownScrollController = ScrollController();
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

  bool _showFileSearch = false;
  final _fileSearchQueryController = TextEditingController();
  final _fileSearchFocusNode = FocusNode();
  final _editorFocusNode = FocusNode();
  bool _fileSearchCaseSensitive = false;
  int _fileSearchCurrentIndex = 0;
  List<TextRange> _fileSearchMatches = const [];

  CodeEditorController _ensureEditor(FrameTokens tokens) {
    if (_editor == null) {
      _editor = CodeEditorController(tokens: tokens, filePath: _editorPath);
    } else {
      _editor!.tokens = tokens;
    }
    return _editor!;
  }

  void _onFileSearchQueryChanged() {
    _updateFileSearch();
  }

  void _openFileSearch() {
    setState(() {
      _showFileSearch = true;
      if (_editor != null &&
          _editor!.selection.isValid &&
          !_editor!.selection.isCollapsed) {
        final start = _editor!.selection.start;
        final end = _editor!.selection.end;
        if (start < end && end <= _editor!.text.length) {
          final selectedText = _editor!.text.substring(start, end);
          if (selectedText.isNotEmpty && !selectedText.contains('\n')) {
            _fileSearchQueryController.text = selectedText;
          }
        }
      }
    });
    _updateFileSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fileSearchFocusNode.requestFocus();
        _fileSearchQueryController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _fileSearchQueryController.text.length,
        );
      }
    });
  }

  void _closeFileSearch() {
    setState(() {
      _showFileSearch = false;
      _editor?.searchQuery = '';
      _fileSearchMatches = const [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editorFocusNode.requestFocus();
    });
  }

  void _updateFileSearch() {
    if (_editor == null) return;
    final query = _fileSearchQueryController.text;
    _editor!.searchQuery = query;
    _editor!.caseSensitive = _fileSearchCaseSensitive;
    final matches = _editor!.findMatches();
    setState(() {
      _fileSearchMatches = matches;
      if (matches.isEmpty) {
        _fileSearchCurrentIndex = 0;
        _editor!.currentMatchIndex = 0;
      } else {
        if (_fileSearchCurrentIndex >= matches.length) {
          _fileSearchCurrentIndex = 0;
        }
        _editor!.currentMatchIndex = _fileSearchCurrentIndex;
        _jumpToMatch(_fileSearchCurrentIndex);
      }
    });
  }

  void _nextFileSearchMatch() {
    if (_fileSearchMatches.isEmpty || _editor == null) return;
    setState(() {
      _fileSearchCurrentIndex =
          (_fileSearchCurrentIndex + 1) % _fileSearchMatches.length;
      _editor!.currentMatchIndex = _fileSearchCurrentIndex;
      _jumpToMatch(_fileSearchCurrentIndex);
    });
  }

  void _prevFileSearchMatch() {
    if (_fileSearchMatches.isEmpty || _editor == null) return;
    setState(() {
      _fileSearchCurrentIndex =
          (_fileSearchCurrentIndex - 1 + _fileSearchMatches.length) %
          _fileSearchMatches.length;
      _editor!.currentMatchIndex = _fileSearchCurrentIndex;
      _jumpToMatch(_fileSearchCurrentIndex);
    });
  }

  void _jumpToMatch(int index) {
    if (_editor == null || index < 0 || index >= _fileSearchMatches.length) {
      return;
    }
    final match = _fileSearchMatches[index];
    _editor!.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
  }

  @override
  void initState() {
    super.initState();
    _fileSearchQueryController.addListener(_onFileSearchQueryChanged);
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
      _editorPath = null;
      _editor?.clear();
      _editor?.filePath = null;
      _searchController.clear();
      _searchQuery = '';
      _showFileSearch = false;
      _previewMarkdown = true;
      _fileSearchQueryController.clear();
      _fileSearchMatches = const [];
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
    _fileSearchQueryController.removeListener(_onFileSearchQueryChanged);
    _fileSearchQueryController.dispose();
    _fileSearchFocusNode.dispose();
    _editorFocusNode.dispose();
    _editor?.dispose();
    _searchController.dispose();
    _markdownScrollController.dispose();
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

  Widget _repoErrorCallout(AppStrings strings, String raw, String title) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: FrameErrorCallout(
          keyPrefix: 'repo-files-error',
          title: title,
          error: describeError(raw, strings),
          strings: strings,
        ),
      ),
    );
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
      return _repoErrorCallout(strings, error, strings.filesLoadFailed);
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

  Widget _editorPane(
    BuildContext context,
    FrameTokens tokens,
    RepositoryState repo,
    String? path,
    WorkspaceFileBuffer? buffer,
    bool writeBlocked,
    String? blockReason, {
    required bool readOnly,
    required bool compact,
  }) {
    final strings = _getStrings();
    if (path == null) {
      return Center(
        child: Text(
          strings.selectAFile,
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }
    if (buffer == null) {
      final error = repo.error;
      if (error == null) {
        return Center(
          child: Text(
            strings.loadingFiles,
            style: TextStyle(color: tokens.textMuted),
          ),
        );
      }
      return _repoErrorCallout(strings, error, strings.filesLoadFailed);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              if (compact)
                IconButton(
                  tooltip: strings.backToFilesTooltip,
                  onPressed: () => ref
                      .read(repositoryStateProvider(widget.sessionId).notifier)
                      .showFileList(),
                  icon: const Icon(Icons.arrow_back, size: 16),
                ),
              Expanded(
                child: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 12,
                    fontFamily: tokens.monoFontFamily,
                  ),
                ),
              ),
              if (buffer.dirty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.warning.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Text(
                    strings.modifiedBadge,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: !buffer.dirty || writeBlocked
                    ? null
                    : () async {
                        if (!context.mounted) return;
                        try {
                          await saveRepositoryFile(
                            context,
                            ref,
                            widget.sessionId,
                            path,
                          );
                        } catch (error) {
                          if (context.mounted) {
                            FrameSnackBar.show(
                              context,
                              message: strings.saveFailed(error),
                            );
                          }
                        }
                      },
                child: Text(strings.save),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: strings.addFileToChatTooltip,
                onPressed: () {
                  appendFileMentionToComposer(ref, widget.sessionId, path);
                  FrameSnackBar.show(
                    context,
                    message: strings.addedFileToChat(path),
                  );
                },
                icon: const Icon(Icons.add_comment_outlined, size: 16),
              ),
              if (path.toLowerCase().endsWith('.md') ||
                  path.toLowerCase().endsWith('.markdown')) ...[
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('repository-markdown-toggle-btn'),
                  tooltip: _previewMarkdown
                      ? strings.editMarkdownSourceTooltip
                      : strings.viewMarkdownPreviewTooltip,
                  onPressed: () {
                    setState(() {
                      _previewMarkdown = !_previewMarkdown;
                    });
                  },
                  icon: Icon(
                    _previewMarkdown
                        ? Icons.edit_note_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: _previewMarkdown ? tokens.accent : tokens.textMuted,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('repository-editor-search-btn'),
                tooltip: strings.searchInFileTooltip,
                onPressed: _openFileSearch,
                icon: Icon(
                  Icons.search,
                  size: 16,
                  color: _showFileSearch ? tokens.accent : tokens.textMuted,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: strings.closeFileTooltip,
                onPressed: () => ref
                    .read(repositoryStateProvider(widget.sessionId).notifier)
                    .showFileList(),
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ),
        if (writeBlocked)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: tokens.signalWarning.withValues(alpha: 0.16),
            child: Text(
              blockReason!,
              style: TextStyle(color: tokens.textSecondary, fontSize: 11),
            ),
          ),
        Expanded(
          child: (path.toLowerCase().endsWith('.md') ||
                      path.toLowerCase().endsWith('.markdown')) &&
                  _previewMarkdown
              ? Container(
                  color: tokens.background,
                  child: Scrollbar(
                    controller: _markdownScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _markdownScrollController,
                      primary: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: SelectionArea(
                        child: RichContent(
                          key: ValueKey('repository-md-preview-$path'),
                          text: buffer.content,
                          cwd: repo.rootPath,
                        ),
                      ),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Focus(
                focusNode: _editorFocusNode,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    final isControl =
                        HardwareKeyboard.instance.isControlPressed ||
                        HardwareKeyboard.instance.isMetaPressed;
                    if (isControl &&
                        event.logicalKey == LogicalKeyboardKey.keyF) {
                      _openFileSearch();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: ValueKey('repository-editor-${widget.sessionId}'),
                  controller: _editor,
                  enabled: !readOnly,
                  onChanged: (value) => ref
                      .read(repositoryStateProvider(widget.sessionId).notifier)
                      .edit(path, value),
                  contextMenuBuilder: (context, editorState) {
                    final selection = editorState.textEditingValue.selection;
                    final items = List<ContextMenuButtonItem>.of(
                      editorState.contextMenuButtonItems,
                    );
                    if (selection.isValid && !selection.isCollapsed) {
                      items.add(
                        ContextMenuButtonItem(
                          label: strings.addPathToChat,
                          onPressed: () {
                            appendCodeSelectionToComposer(
                              ref,
                              widget.sessionId,
                              path,
                              editorState.textEditingValue.text,
                              selection,
                            );
                            editorState.hideToolbar();
                          },
                        ),
                      );
                    }
                    return AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editorState.contextMenuAnchors,
                      buttonItems: items,
                    );
                  },
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(
                    fontFamily: tokens.monoFontFamily,
                    fontSize: 12,
                    color: tokens.textPrimary,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: tokens.background,
                    contentPadding: const EdgeInsets.all(12),
                    border: InputBorder.none,
                    hintText: writeBlocked ? strings.readOnlyBlockedReason : strings.fileContentHint,
                  ),
                ),
              ),
              if (_showFileSearch)
                Positioned(
                  top: 8,
                  right: 16,
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.escape) {
                          _closeFileSearch();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                                LogicalKeyboardKey.enter ||
                            event.logicalKey ==
                                LogicalKeyboardKey.numpadEnter) {
                          if (HardwareKeyboard.instance.isShiftPressed) {
                            _prevFileSearchMatch();
                          } else {
                            _nextFileSearchMatch();
                          }
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Container(
                      key: const ValueKey('repository-file-search-bar'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(color: tokens.borderStrong),
                        boxShadow: [
                          BoxShadow(
                            color: tokens.borderStrong.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search, size: 14, color: tokens.textMuted),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 170,
                            height: 26,
                            child: TextField(
                              key: const ValueKey(
                                'repository-file-search-field',
                              ),
                              controller: _fileSearchQueryController,
                              focusNode: _fileSearchFocusNode,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 12,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: strings.searchInFileHint,
                                hintStyle: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 12,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.surface,
                              borderRadius: BorderRadius.circular(
                                tokens.radiusSm,
                              ),
                            ),
                            child: Text(
                              _fileSearchQueryController.text.isEmpty
                                  ? ''
                                  : _fileSearchMatches.isEmpty
                                  ? strings.zeroResults
                                  : strings.searchResultsCount(
                                      _fileSearchCurrentIndex + 1,
                                      _fileSearchMatches.length,
                                    ),
                              style: TextStyle(
                                color:
                                    _fileSearchMatches.isEmpty &&
                                        _fileSearchQueryController
                                            .text
                                            .isNotEmpty
                                    ? tokens.danger
                                    : tokens.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            key: const ValueKey('repository-file-search-prev'),
                            tooltip: strings.previousMatchTooltip,
                            icon: const Icon(Icons.keyboard_arrow_up, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 22,
                              minHeight: 22,
                            ),
                            onPressed: _fileSearchMatches.isEmpty
                                ? null
                                : _prevFileSearchMatch,
                          ),
                          IconButton(
                            key: const ValueKey('repository-file-search-next'),
                            tooltip: strings.nextMatchTooltip,
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              size: 16,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 22,
                              minHeight: 22,
                            ),
                            onPressed: _fileSearchMatches.isEmpty
                                ? null
                                : _nextFileSearchMatch,
                          ),
                          IconButton(
                            key: const ValueKey('repository-file-search-case'),
                            tooltip: strings.matchCaseTooltip,
                            icon: Text(
                              'Aa',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _fileSearchCaseSensitive
                                    ? tokens.accent
                                    : tokens.textMuted,
                              ),
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 22,
                              minHeight: 22,
                            ),
                            onPressed: () {
                              setState(() {
                                _fileSearchCaseSensitive =
                                    !_fileSearchCaseSensitive;
                              });
                              _updateFileSearch();
                            },
                          ),
                          IconButton(
                            key: const ValueKey('repository-file-search-close'),
                            tooltip: strings.closeFileSearchTooltip,
                            icon: const Icon(Icons.close, size: 14),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 22,
                              minHeight: 22,
                            ),
                            onPressed: _closeFileSearch,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final editor = _ensureEditor(tokens);
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
    final buffer = path == null ? null : repo.buffers[path];
    if (path != _editorPath) {
      _editorPath = path;
      _previewMarkdown = true;
      editor.filePath = path;
      editor.value = TextEditingValue(text: buffer?.content ?? '');
      if (_showFileSearch) {
        _updateFileSearch();
      }
    } else if (buffer != null && editor.text != buffer.content) {
      editor.filePath = path;
      editor.value = TextEditingValue(
        text: buffer.content,
        selection: TextSelection.collapsed(offset: buffer.content.length),
      );
      if (_showFileSearch) {
        _updateFileSearch();
      }
    }
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
                    upperContent = _editorPane(
                      context,
                      tokens,
                      repo,
                      path,
                      buffer,
                      writeBlocked,
                      blockReason,
                      readOnly: readOnly,
                      compact: true,
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
                          child: _editorPane(
                            context,
                            tokens,
                            repo,
                            path,
                            buffer,
                            writeBlocked,
                            blockReason,
                            readOnly: readOnly,
                            compact: false,
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
