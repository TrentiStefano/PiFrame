import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';
import '../composer/composer_draft.dart';
import '../../ui/code/code_editor_controller.dart';
import '../../ui/code/diff_block.dart';
import '../../data/terminal/terminal_settings.dart';
import 'integrated_terminal.dart';
import '../../ui/code/file_icon.dart';
import '../transcript/rich_content.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/motion.dart';
import '../browser/browser_controller.dart';
import '../browser/browser_models.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_workspace.dart';
import '../session_changes/session_changes_provider.dart';
import 'branch_picker_dialog.dart';

enum WorkspacePane { chat, repository, git }

final repoExpandedDirsProvider = StateProvider.family<Set<String>, String>(
  (ref, sessionId) => <String>{},
);

final gitStagedExpandedProvider = StateProvider.family<bool, String>(
  (ref, sessionId) => false,
);

final gitUnstagedExpandedProvider = StateProvider.family<bool, String>(
  (ref, sessionId) => false,
);

String _repositoryLoadError(Object error, [AppStrings? strings]) {
  final message = error.toString();
  if (message.contains('Unsupported command type: workspace.listFiles')) {
    return strings?.repositoryDaemonOutdatedError ??
        'Daemon obsoleto: esegui `pnpm run build:agentd`, ricostruisci PiFrame e riavvia il daemon solo quando nessun worker Pi è attivo.';
  }
  return message;
}

Set<String> piTouchedPaths(SessionState session) {
  final paths = <String>{};
  final tools = [
    ...session.entries.expand((entry) => entry.toolCalls),
    ...session.activeToolCalls.values,
  ];
  for (final tool in tools) {
    if (!const {'write', 'edit'}.contains(tool.toolName.toLowerCase()) ||
        tool.isError) {
      continue;
    }
    final rawPath = tool.args['path']?.toString();
    if (rawPath == null || rawPath.isEmpty) continue;
    final candidate = rawPath.replaceAll('\\', '/');
    final root = session.cwd
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/$'), '');
    final rootPrefix = '$root/';
    if (candidate.toLowerCase().startsWith(rootPrefix.toLowerCase())) {
      paths.add(candidate.substring(rootPrefix.length));
    } else if (!candidate.startsWith('/') &&
        !RegExp(r'^[a-zA-Z]:').hasMatch(candidate)) {
      paths.add(candidate.replaceFirst(RegExp(r'^\./'), ''));
    }
  }
  return paths;
}

Set<String> _piTouchedPaths(SessionState session) => piTouchedPaths(session);

bool _pathSetContains(Set<String> paths, String path) =>
    paths.contains(path) ||
    paths.any((value) => value.toLowerCase() == path.toLowerCase());

String _changeOriginLabel(
  String path,
  Set<String> piTouchedPaths,
  Set<String> manualSavedPaths, [
  AppStrings? strings,
]) {
  final touchedByPi = _pathSetContains(piTouchedPaths, path);
  final savedHere = _pathSetContains(manualSavedPaths, path);
  if (touchedByPi && savedHere) {
    return strings?.gitOriginPiAndManual ?? 'Tool Pi + salvataggio PiFrame';
  }
  if (touchedByPi) {
    return strings?.gitOriginPiTool ?? 'Tool Pi ha scritto il percorso';
  }
  if (savedHere) {
    return strings?.gitOriginManualSave ?? 'Salvato da te in PiFrame';
  }
  return strings?.gitOriginUndetermined ?? 'Origine non determinata';
}

bool _sessionWritesBlocked(SessionState session) =>
    session.readOnly ||
    const {
      AgentStatus.working,
      AgentStatus.retrying,
      AgentStatus.compacting,
      AgentStatus.awaitingUser,
    }.contains(session.agentStatus);

class WorkspaceFileBuffer {
  final String content;
  final String savedContent;
  final String revision;
  const WorkspaceFileBuffer(this.content, this.savedContent, this.revision);
  bool get dirty => content != savedContent;
}

class RepositoryState {
  final String? rootPath;
  final List<Map<String, dynamic>> files;
  final String? selectedPath;
  final Map<String, WorkspaceFileBuffer> buffers;
  final Set<String> manualSavedPaths;
  final bool loading;
  final bool truncated;
  final String? error;
  const RepositoryState({
    this.rootPath,
    this.files = const [],
    this.selectedPath,
    this.buffers = const {},
    this.manualSavedPaths = const {},
    this.loading = false,
    this.truncated = false,
    this.error,
  });
  bool get dirty => buffers.values.any((buffer) => buffer.dirty);
}

final repositoryStateProvider =
    StateNotifierProvider.family<RepositoryController, RepositoryState, String>(
      (ref, sessionId) {
        return RepositoryController(
          sessionId,
          () => ref.read(pcpClientProvider),
          () => ref.read(appStringsProvider),
        );
      },
    );

class RepositoryController extends StateNotifier<RepositoryState> {
  RepositoryController(
    this.sessionId,
    this._readClient, [
    this._readStrings,
  ]) : super(const RepositoryState());
  final String sessionId;
  final PcpClient? Function() _readClient;
  final AppStrings Function()? _readStrings;

  RepositoryState get currentState => state;

  Future<void> loadFiles() async {
    final client = _readClient();
    if (client == null) {
      state = RepositoryState(
        error: _readStrings?.call().daemonNotConnectedCapital ??
            'Daemon non connesso',
      );
      return;
    }
    state = RepositoryState(
      rootPath: state.rootPath,
      files: state.files,
      selectedPath: state.selectedPath,
      buffers: state.buffers,
      manualSavedPaths: state.manualSavedPaths,
      loading: true,
    );
    try {
      final result = await client.listWorkspaceFiles(sessionId);
      final data = (result['data'] as Map<String, dynamic>?) ?? result;
      final files = (data['files'] as List? ?? []).cast<Map<String, dynamic>>();
      state = RepositoryState(
        rootPath: data['rootPath'] as String?,
        files: files,
        selectedPath: state.selectedPath,
        buffers: state.buffers,
        manualSavedPaths: state.manualSavedPaths,
        truncated: data['truncated'] == true,
      );
    } catch (error) {
      state = RepositoryState(
        rootPath: state.rootPath,
        files: state.files,
        selectedPath: state.selectedPath,
        buffers: state.buffers,
        manualSavedPaths: state.manualSavedPaths,
        error: _repositoryLoadError(error, _readStrings?.call()),
      );
    }
  }

  Future<void> selectFile(String path) async {
    final client = _readClient();
    final buffers = Map<String, WorkspaceFileBuffer>.of(state.buffers)
      ..removeWhere(
        (existingPath, buffer) => existingPath != path && !buffer.dirty,
      );
    final cached = buffers[path];
    state = RepositoryState(
      rootPath: state.rootPath,
      files: state.files,
      selectedPath: path,
      buffers: buffers,
      manualSavedPaths: state.manualSavedPaths,
      truncated: state.truncated,
    );
    if (cached != null || client == null) return;
    try {
      final result = await client.readWorkspaceFile(sessionId, path);
      final data = (result['data'] as Map<String, dynamic>?) ?? result;
      final updatedBuffers = Map<String, WorkspaceFileBuffer>.of(state.buffers);
      updatedBuffers[path] = WorkspaceFileBuffer(
        data['content'] as String,
        data['content'] as String,
        data['revision'].toString(),
      );
      state = RepositoryState(
        rootPath: data['rootPath'] as String? ?? state.rootPath,
        files: state.files,
        selectedPath: state.selectedPath,
        buffers: updatedBuffers,
        manualSavedPaths: state.manualSavedPaths,
        truncated: state.truncated,
      );
    } catch (error) {
      state = RepositoryState(
        rootPath: state.rootPath,
        files: state.files,
        selectedPath: path,
        buffers: state.buffers,
        manualSavedPaths: state.manualSavedPaths,
        error: error.toString(),
        truncated: state.truncated,
      );
    }
  }

  void showFileList() {
    state = RepositoryState(
      rootPath: state.rootPath,
      files: state.files,
      buffers: state.buffers,
      manualSavedPaths: state.manualSavedPaths,
      truncated: state.truncated,
      error: state.error,
    );
  }

  void edit(String path, String content) {
    final current = state.buffers[path];
    if (current == null) return;
    final buffers = Map<String, WorkspaceFileBuffer>.of(state.buffers);
    buffers[path] = WorkspaceFileBuffer(
      content,
      current.savedContent,
      current.revision,
    );
    state = RepositoryState(
      rootPath: state.rootPath,
      files: state.files,
      selectedPath: state.selectedPath,
      buffers: buffers,
      manualSavedPaths: state.manualSavedPaths,
      truncated: state.truncated,
    );
  }

  Future<void> save(String path, {String? revisionOverride}) async {
    final client = _readClient();
    final buffer = state.buffers[path];
    if (client == null || buffer == null) {
      throw StateError('File non disponibile');
    }
    final content = buffer.content;
    final result = await client.saveWorkspaceFile(sessionId, {
      'path': path,
      'content': content,
      'revision': revisionOverride ?? buffer.revision,
    });
    final data = (result['data'] as Map<String, dynamic>?) ?? result;
    final buffers = Map<String, WorkspaceFileBuffer>.of(state.buffers);
    buffers[path] = WorkspaceFileBuffer(
      content,
      content,
      data['revision'].toString(),
    );
    final manualSavedPaths = Set<String>.of(state.manualSavedPaths)..add(path);
    state = RepositoryState(
      rootPath: state.rootPath,
      files: state.files,
      selectedPath: state.selectedPath,
      buffers: buffers,
      manualSavedPaths: manualSavedPaths,
      truncated: state.truncated,
    );
  }

  void clearManualSavedPaths(Iterable<String> paths) {
    final manualSavedPaths = Set<String>.of(state.manualSavedPaths)
      ..removeAll(paths);
    if (manualSavedPaths.length == state.manualSavedPaths.length) return;
    state = RepositoryState(
      rootPath: state.rootPath,
      files: state.files,
      selectedPath: state.selectedPath,
      buffers: state.buffers,
      manualSavedPaths: manualSavedPaths,
      truncated: state.truncated,
    );
  }

  Future<({String content, String revision})> currentDisk(String path) async {
    final client = _readClient();
    if (client == null) throw StateError('Daemon non connesso');
    final result = await client.readWorkspaceFile(sessionId, path);
    final data = (result['data'] as Map<String, dynamic>?) ?? result;
    return (
      content: data['content'] as String,
      revision: data['revision'].toString(),
    );
  }

  void reload(String path, String content, String revision) {
    final buffers = Map<String, WorkspaceFileBuffer>.of(state.buffers);
    buffers[path] = WorkspaceFileBuffer(content, content, revision);
    state = RepositoryState(
      rootPath: state.rootPath,
      files: state.files,
      selectedPath: state.selectedPath,
      buffers: buffers,
      manualSavedPaths: state.manualSavedPaths,
      truncated: state.truncated,
    );
  }

  void discardDirty() {
    final buffers = Map<String, WorkspaceFileBuffer>.of(state.buffers);
    for (final entry in buffers.entries.toList()) {
      if (entry.value.dirty) {
        buffers[entry.key] = WorkspaceFileBuffer(
          entry.value.savedContent,
          entry.value.savedContent,
          entry.value.revision,
        );
      }
    }
    state = RepositoryState(
      rootPath: state.rootPath,
      files: state.files,
      selectedPath: state.selectedPath,
      buffers: buffers,
      manualSavedPaths: state.manualSavedPaths,
      truncated: state.truncated,
    );
  }
}

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
  final writesBlocked = _sessionWritesBlocked(session);
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
  if (_sessionWritesBlocked(session)) {
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
      return Center(
        child: Text(
          repo.error ?? strings.noFilesAvailable,
          style: TextStyle(
            color: repo.error == null ? tokens.textMuted : tokens.danger,
          ),
        ),
      );
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
      return Center(
        child: Text(
          repo.error ?? strings.loadingFiles,
          style: TextStyle(
            color: repo.error == null ? tokens.textMuted : tokens.danger,
          ),
        ),
      );
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
          _paneHeader(
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

class GitChangesPane extends ConsumerStatefulWidget {
  const GitChangesPane({
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
  ConsumerState<GitChangesPane> createState() => _GitChangesPaneState();
}

class _GitChangesPaneState extends ConsumerState<GitChangesPane> {
  Map<String, dynamic>? _status;
  bool _loading = false;
  bool _working = false;
  bool _branchPickerOpen = false;
  final _message = TextEditingController();
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(GitChangesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _status = null;
      _refresh();
    }
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void>? _refreshing;
  bool _refreshAgain = false;

  /// Opening a session fires several refresh triggers in a row (cwd, idle, touched files). While one
  /// refresh runs, further requests collapse into a single follow-up, so the result is still current.
  Future<void> _refresh() {
    if (_refreshing != null) {
      _refreshAgain = true;
      return _refreshing!;
    }
    return _refreshing = () async {
      try {
        do {
          _refreshAgain = false;
          await _refreshOnce();
        } while (_refreshAgain && mounted);
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<void> _refreshOnce() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      if (mounted) setState(() => _status = {'error': 'Daemon non connesso'});
      return;
    }
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final result = await client.refreshWorkspace(widget.sessionId);
      if (mounted) {
        setState(() => _status = (result['data'] as Map<String, dynamic>?) ?? result);
      }
    } catch (e) {
      if (mounted) setState(() => _status = {'error': e.toString()});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _files =>
      ((_status?['files'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .toList();
  List<String> get _staged =>
      _files
          .where((f) => f['staged'] == true)
          .map((f) => f['path'].toString())
          .toList()
        ..sort();
  Future<void> _action(
    String action,
    List<String> paths, {
    String? message,
    List<String>? expected,
  }) async {
    if (_working || (paths.isEmpty && !_remoteActions.contains(action))) return;
    setState(() => _working = true);
    try {
      await ref.read(pcpClientProvider)!.workspaceGitAction(widget.sessionId, {
        'action': action,
        'paths': paths,
        'expectedStagedPaths': ?expected,
        'message': ?message,
      });
      if (action == 'discard' || action == 'commit') {
        ref
            .read(repositoryStateProvider(widget.sessionId).notifier)
            .clearManualSavedPaths(paths);
      }
      await _refresh();
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(
          context,
          message: strings.gitOperationFailed(error),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  static const _remoteActions = {'fetch', 'pull', 'push', 'sync'};

  Widget _remoteButton({
    required String action,
    required IconData icon,
    required String label,
    required String tooltip,
    required bool enabled,
    required FrameTokens tokens,
  }) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          key: ValueKey('git-$action-btn'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            minimumSize: const Size(0, 30),
            visualDensity: VisualDensity.compact,
            foregroundColor: tokens.textPrimary,
            side: BorderSide(color: tokens.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
          ),
          onPressed: enabled ? () => _action(action, const []) : null,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openBranchPicker() async {
    final session = ref.read(sessionStateFamily(widget.sessionId));
    final readOnly = session.readOnly;
    final agentStatus = session.agentStatus;
    final blocked =
        readOnly ||
        const {
          AgentStatus.working,
          AgentStatus.retrying,
          AgentStatus.compacting,
          AgentStatus.awaitingUser,
        }.contains(agentStatus);
    if (_branchPickerOpen || _loading || _working || blocked) return;
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    _branchPickerOpen = true;
    try {
      final current = _status?['branch']?.toString();
      final targetBranch = await BranchPickerDialog.show(
        context,
        sessionId: widget.sessionId,
        client: client,
        currentBranch: current,
      );
      if (targetBranch != null && mounted) {
        await _handleSwitchBranch(targetBranch);
      }
    } finally {
      _branchPickerOpen = false;
    }
  }

  Future<void> _handleSwitchBranch(String branch, {bool stash = false}) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    final strings = ref.read(appStringsProvider);
    setState(() => _loading = true);
    try {
      final result = await client.switchBranch(
        widget.sessionId,
        branch,
        onDirty: stash ? 'stash' : 'block',
      );
      await _refresh();
      try {
        await ref
            .read(sessionChangesProvider(widget.sessionId).notifier)
            .refresh();
      } catch (_) {}
      if (!mounted) return;
      if (result.stashed) {
        FrameSnackBar.show(
          context,
          message:
              '${strings.branchSwitched(branch)}. ${strings.branchSwitchedStashNotice(result.stashMessage ?? '')}',
        );
      } else {
        FrameSnackBar.show(
          context,
          message: strings.branchSwitched(branch),
        );
      }
    } catch (error) {
      if (!mounted) return;
      if (error is PcpException) {
        if (error.code == 'WORKSPACE_DIRTY') {
          final shouldStash = await _showDirtyWorkspaceDialog(
            changedFiles: error.changedFiles,
            untrackedFiles: error.untrackedFiles,
          );
          if (shouldStash == true && mounted) {
            await _handleSwitchBranch(branch, stash: true);
          }
          return;
        } else if (error.code == 'BRANCH_SWITCH_FAILED') {
          await _showBranchSwitchFailedDialog(
            stderr: error.stderr ?? error.message,
            stashRetained: error.stashRetained,
            stashMessage: error.stashMessage,
          );
          return;
        } else if (error.code == 'COMMAND_REJECTED' ||
            error.message.toLowerCase().contains('read-only') ||
            error.message.toLowerCase().contains('busy') ||
            error.message.toLowerCase().contains('working')) {
          FrameSnackBar.show(
            context,
            message: strings.branchSwitchAgentWorking,
          );
          return;
        } else if (error.code == 'BRANCH_NOT_FOUND') {
          FrameSnackBar.show(context, message: strings.branchNotFound);
          await _refresh();
          return;
        } else if (error.code == 'BRANCH_INVALID_NAME') {
          FrameSnackBar.show(context, message: strings.branchInvalidName);
          await _refresh();
          return;
        }
      }
      final msg = error.toString();
      if (msg.toLowerCase().contains('read-only') ||
          msg.toLowerCase().contains('working') ||
          msg.toLowerCase().contains('busy') ||
          msg.toLowerCase().contains('active')) {
        FrameSnackBar.show(context, message: strings.branchSwitchAgentWorking);
      } else if (msg.contains('BRANCH_NOT_FOUND')) {
        FrameSnackBar.show(context, message: strings.branchNotFound);
        await _refresh();
      } else {
        FrameSnackBar.show(context, message: msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool?> _showDirtyWorkspaceDialog({
    required int changedFiles,
    required int untrackedFiles,
  }) {
    final strings = ref.read(appStringsProvider);
    final tokens = context.tokens;
    var popped = false;
    void popOnce(BuildContext dialogContext, bool result) {
      if (popped) return;
      popped = true;
      Navigator.of(dialogContext).pop(result);
    }

    return showDialog<bool>(
      context: context,
      barrierColor: tokens.overlay,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            side: BorderSide(color: tokens.border),
          ),
          title: Text(
            strings.workspaceDirtyDialogTitle,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            strings.workspaceDirtyDialogMessage(changedFiles, untrackedFiles),
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 14,
            ),
          ),
          actions: [
            OutlinedButton(
              key: const ValueKey('git-cancel-switch-btn'),
              autofocus: true,
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.textPrimary,
                side: BorderSide(color: tokens.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
              ),
              onPressed: () => popOnce(dialogContext, false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              key: const ValueKey('git-stash-and-switch-btn'),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
              ),
              onPressed: () => popOnce(dialogContext, true),
              child: Text(strings.stashAndSwitchBtn),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBranchSwitchFailedDialog({
    required String stderr,
    required bool stashRetained,
    String? stashMessage,
  }) {
    final strings = ref.read(appStringsProvider);
    final tokens = context.tokens;
    final truncatedStderr =
        stderr.length > 2048 ? '${stderr.substring(0, 2048)}\n…' : stderr;
    var popped = false;
    void popOnce(BuildContext dialogContext) {
      if (popped) return;
      popped = true;
      Navigator.of(dialogContext).pop();
    }

    return showDialog<void>(
      context: context,
      barrierColor: tokens.overlay,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            side: BorderSide(color: tokens.border),
          ),
          title: Row(
            children: [
              Icon(Icons.error_outline, color: tokens.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.branchSwitchFailedTitle,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stashRetained) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: tokens.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(
                          color: tokens.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: tokens.warning,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              strings.stashRetainedSafeNotice(
                                stashMessage ?? '',
                              ),
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.background,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border),
                    ),
                    child: SelectableText(
                      truncatedStderr,
                      style: TextStyle(
                        fontFamily: tokens.monoFontFamily,
                        fontSize: 12,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
              ),
              onPressed: () => popOnce(dialogContext),
              child: Text(strings.close),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDiff(String path) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      final result = await client.getWorkspaceDiff(
        widget.sessionId,
        filePath: path,
      );
      final diff = (result['data']?['diff'] ?? result['diff'])?.toString() ?? '';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final tokens = dialogContext.tokens;
          return Dialog(
            backgroundColor: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              side: BorderSide(color: tokens.border, width: 1),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: context.tokens.monoFontFamily,
                              color: context.tokens.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: ref.read(appStringsProvider).closeDiffTooltip,
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: DiffBlock(
                          diffText: diff.isEmpty
                              ? ref.read(appStringsProvider).noDifferencesFound
                              : diff,
                          filename: path,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(
          context,
          message: strings.diffUnavailable(error),
        );
      }
    }
  }

  Future<void> _discardFile(String path) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    var diff = '';
    try {
      final result = await client.getWorkspaceDiff(
        widget.sessionId,
        filePath: path,
      );
      diff = (result['data']?['diff'] ?? result['diff'])?.toString() ?? '';
    } catch (_) {}
    if (!mounted) return;
    final strings = ref.read(appStringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.discardAllChangesTitle),
        content: Builder(
          builder: (dialogContext) {
            final mediaSize = MediaQuery.sizeOf(dialogContext);
            return SizedBox(
              width: (mediaSize.width * 0.8).clamp(280.0, 640.0),
              height: (mediaSize.height * 0.6).clamp(240.0, 380.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.discardAllChangesWarning,
                    key: const ValueKey('discard-file-warning'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$path\n${_status?['rootPath'] ?? '—'} · ${_status?['branch'] ?? '—'}',
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: DiffBlock(
                        diffText: diff.isEmpty ? strings.diffUnavailableShort : diff,
                        filename: path,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            key: const ValueKey('discard-file-cancel-btn'),
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const ValueKey('discard-file-confirm-btn'),
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.tokens.danger,
              foregroundColor: dialogContext.tokens.surface,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.discardChangesBtn),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) await _action('discard', [path]);
  }

  Future<void> _commit() async {
    final staged = _staged;
    if (staged.isEmpty) return;
    final strings = ref.read(appStringsProvider);
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.commitStagedFilesTitle),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: (MediaQuery.sizeOf(ctx).height * 0.6).clamp(
              200.0,
              420.0,
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.commitDialogDetails(
                    root: _status?['rootPath']?.toString() ?? '—',
                    branch: _status?['branch']?.toString() ?? '—',
                    count: staged.length,
                    filesPreview: staged.take(5).join(', '),
                    remaining: staged.length > 5 ? staged.length - 5 : 0,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _message,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: strings.commitMessageLabel,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _message.text.trim()),
            child: Text(strings.commitAction),
          ),
        ],
      ),
    );
    if (message == null || message.isEmpty) return;
    _message.clear();
    await _action('commit', staged, message: message, expected: staged);
  }

  Widget _buildGitSectionHeader({
    required String title,
    required int count,
    required bool isExpanded,
    required VoidCallback onToggle,
    required FrameTokens tokens,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onToggle,
      hoverColor: tokens.accent.withValues(alpha: 0.05),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated.withValues(alpha: 0.6),
          border: Border(
            top: BorderSide(color: tokens.borderStrong, width: 0.5),
            bottom: BorderSide(color: tokens.borderStrong, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isExpanded ? Icons.expand_more : Icons.chevron_right,
              size: 16,
              color: tokens.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                color: tokens.displayText,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            ?trailing,
          ],
        ),
      ),
    );
  }

  /// Each row fades in where it appears, so a file moving between Staged and Changes is visible.
  Widget _buildGitFileRow({
    required Map<String, dynamic> file,
    required bool isStaged,
    required bool hasUnstagedEdit,
    required FrameTokens tokens,
    required Set<String> piTouchedPaths,
    required Set<String> manualSavedPaths,
    required bool blocked,
    required AppStrings strings,
  }) {
    return FrameEnter(
      key: ValueKey('git-row-${isStaged ? 'staged' : 'unstaged'}-${file['path']}'),
      offset: 4,
      duration: FrameMotion.small,
      child: _gitFileRowBody(
        file: file,
        isStaged: isStaged,
        hasUnstagedEdit: hasUnstagedEdit,
        tokens: tokens,
        piTouchedPaths: piTouchedPaths,
        manualSavedPaths: manualSavedPaths,
        blocked: blocked,
        strings: strings,
      ),
    );
  }

  Widget _gitFileRowBody({
    required Map<String, dynamic> file,
    required bool isStaged,
    required bool hasUnstagedEdit,
    required FrameTokens tokens,
    required Set<String> piTouchedPaths,
    required Set<String> manualSavedPaths,
    required bool blocked,
    required AppStrings strings,
  }) {
    final path = file['path'].toString();
    final stateLabel = isStaged && hasUnstagedEdit
        ? 'staged + unstaged edits'
        : isStaged
        ? 'staged'
        : 'unstaged';

    return Material(
      color: tokens.surface.withValues(alpha: 0),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        minVerticalPadding: 0,
        contentPadding: const EdgeInsets.only(left: 16, right: 8),
        onTap: () => _showDiff(path),
        leading: FileIcon(path: path, size: 16),
        title: Text(
          path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 12,
            fontFamily: tokens.uiFontFamily,
          ),
        ),
        subtitle: Text(
          '${file['status'] ?? 'modified'} · $stateLabel · ${_changeOriginLabel(path, piTouchedPaths, manualSavedPaths, strings)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isStaged ? tokens.accent : tokens.textMuted,
            fontSize: 9,
          ),
        ),
        trailing: SizedBox(
          width: 88,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isStaged)
                IconButton(
                  tooltip: strings.unstageFileTooltip(path),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: blocked || _working
                      ? null
                      : () => _action('unstage', [path]),
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                )
              else if (hasUnstagedEdit || !isStaged)
                IconButton(
                  tooltip: strings.stageFileTooltip(path),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: blocked || _working
                      ? null
                      : () => _action('stage', [path]),
                  icon: const Icon(Icons.add, size: 17),
                ),
              IconButton(
                tooltip: strings.discardFileTooltip(path),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: blocked || _working
                    ? null
                    : () => _discardFile(path),
                icon: const Icon(Icons.undo, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final (readOnly, readOnlyReason, agentStatus, cwd, touchedKey) = ref.watch(
      sessionStateFamily(widget.sessionId).select(
        (s) => (
          s.readOnly,
          s.readOnlyReason,
          s.agentStatus,
          s.cwd,
          _piTouchedPaths(s).join('\x00'),
        ),
      ),
    );
    final repository = ref.watch(repositoryStateProvider(widget.sessionId));

    ref.listen<String>(
      sessionStateFamily(widget.sessionId).select((s) => s.cwd),
      (prev, next) {
        if (next.isNotEmpty &&
            (prev == null || prev.isEmpty || _status?['error'] != null)) {
          _refresh();
        }
      },
    );

    ref.listen<String>(
      sessionStateFamily(widget.sessionId).select((s) => _piTouchedPaths(s).join('\x00')),
      (prev, next) {
        if (prev != null && prev != next) {
          _refresh();
        }
      },
    );

    ref.listen<AgentStatus>(
      sessionStateFamily(widget.sessionId).select((s) => s.agentStatus),
      (prev, next) {
        if (prev != null && prev != next && next == AgentStatus.idle) {
          _refresh();
        }
      },
    );

    final piTouchedPaths = touchedKey.isEmpty
        ? const <String>{}
        : touchedKey.split('\x00').toSet();
    final blocked =
        readOnly ||
        const {
          AgentStatus.working,
          AgentStatus.retrying,
          AgentStatus.compacting,
          AgentStatus.awaitingUser,
        }.contains(agentStatus);
    final files = _files;
    final staged = _staged.toSet();
    final stagedFiles = files
        .where((f) => staged.contains(f['path'].toString()))
        .toList();
    final unstagedFiles = files
        .where(
          (f) =>
              f['unstaged'] == true || !staged.contains(f['path'].toString()),
        )
        .toList();
    final isStagedExpanded = ref.watch(
      gitStagedExpandedProvider(widget.sessionId),
    );
    final isUnstagedExpanded = ref.watch(
      gitUnstagedExpandedProvider(widget.sessionId),
    );
    final repo = _status?['isRepository'] == true;
    final root = _status?['rootPath']?.toString() ?? cwd;
    return Container(
      decoration: BoxDecoration(color: tokens.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _paneHeader(
            context,
            'Git Changes',
            Icons.source_outlined,
            companionTabs: widget.companionTabs,
            activeCompanionTab: widget.activeCompanionTab ?? WorkspacePane.git,
            onSelectCompanionTab: widget.onSelectCompanionTab,
            titleWidget: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Icon(Icons.source_outlined, size: 16, color: tokens.accent),
                  const SizedBox(width: 8),
                  Text(
                    'GIT CHANGES',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 11.5,
                      fontFamily: tokens.uiFontFamily,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  if (ref.watch(browserPaneSupportedProvider)) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      key: const ValueKey('right-pane-switch-browser-chip'),
                      onTap: () {
                        ref.read(rightPaneModeProvider.notifier).state =
                            RightPaneMode.browser;
                      },
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.language,
                              size: 12,
                              color: tokens.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Browser',
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ref.watch(browserPaneSupportedProvider))
                  IconButton(
                    key: const ValueKey('git-switch-to-browser-btn'),
                    tooltip: strings.switchToWebBrowserTooltip,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    onPressed: () {
                      ref.read(rightPaneModeProvider.notifier).state =
                          RightPaneMode.browser;
                    },
                    icon: const Icon(Icons.language, size: 16),
                  ),
                IconButton(
                  tooltip: strings.refreshGitStatusTooltip,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                ),
                if (widget.onCollapse != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    tooltip: strings.collapseGitPanelTooltip,
                    onPressed: widget.onCollapse,
                    icon: const Icon(Icons.chevron_right, size: 18),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    root,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 10,
                      fontFamily: tokens.monoFontFamily,
                    ),
                  ),
                ),
                if (repo || _status?['branch'] != null || _status?['detached'] == true) ...[
                  const SizedBox(width: 6),
                  Builder(
                    builder: (context) {
                      final branchDisabled = blocked || _working || _loading;
                      final chipTooltip = (blocked && !readOnly)
                          ? strings.branchSwitchAgentWorking
                          : strings.branchChipTooltip;
                      return Tooltip(
                        message: chipTooltip,
                        child: InkWell(
                          key: const ValueKey('git-branch-chip'),
                          onTap: branchDisabled ? null : _openBranchPicker,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.surface,
                              borderRadius: BorderRadius.circular(tokens.radiusSm),
                              border: Border.all(color: tokens.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fork_right,
                                  size: 13,
                                  color: branchDisabled
                                      ? tokens.textMuted
                                      : tokens.accent,
                                ),
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 160),
                                  child: Text(
                                    _status?['detached'] == true
                                        ? (_status?['headShortSha']?.toString() ??
                                            'detached')
                                        : (_status?['branch']?.toString() ?? '—'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: branchDisabled
                                          ? tokens.textMuted
                                          : tokens.textPrimary,
                                      fontSize: 11,
                                      fontFamily: tokens.monoFontFamily,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          if (blocked)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tokens.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(color: tokens.border),
                ),
                child: Text(
                  readOnly
                      ? strings.writesDisabledReadOnly(readOnlyReason)
                      : strings.writesDisabledPiWorking,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 11),
                ),
              ),
            ),
          if (!repo)
            Builder(
              builder: (context) {
                final rawError = _status?['error']?.toString();
                final isAttaching =
                    (rawError != null &&
                        (rawError.contains('not found') ||
                            rawError.contains('Session not found'))) ||
                    (_status == null && cwd.isEmpty);

                if (_loading || isAttaching) {
                  return Expanded(
                    child: Center(
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
                            strings.connectingToGit,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Expanded(
                  child: Center(
                    child: Text(
                      rawError ?? strings.noGitRepository,
                      style: TextStyle(
                        color: rawError == null
                            ? tokens.textMuted
                            : tokens.danger,
                      ),
                    ),
                  ),
                );
              },
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 4,
                children: [
                  Text(
                    strings.gitFilesCount(files.length),
                    style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                  ),
                  Text(
                    '+${_status?['totalAdditions'] ?? 0}',
                    style: TextStyle(color: tokens.diffAddedFg, fontSize: 11),
                  ),
                  Text(
                    '-${_status?['totalDeletions'] ?? 0}',
                    style: TextStyle(color: tokens.diffRemovedFg, fontSize: 11),
                  ),
                ],
              ),
            ),
            Expanded(
              child: files.isEmpty
                  ? Center(
                      child: Text(
                        strings.workingTreeClean,
                        style: TextStyle(color: tokens.textMuted),
                      ),
                    )
                  : ListView(
                      children: [
                        _buildGitSectionHeader(
                          title: strings.stagedChangesSectionUpper,
                          count: stagedFiles.length,
                          isExpanded: isStagedExpanded,
                          tokens: tokens,
                          onToggle: () {
                            ref
                                    .read(
                                      gitStagedExpandedProvider(
                                        widget.sessionId,
                                      ).notifier,
                                    )
                                    .state =
                                !isStagedExpanded;
                          },
                          trailing: stagedFiles.isEmpty || blocked || _working
                              ? null
                              : IconButton(
                                  tooltip: strings.unstageAllTooltip,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    size: 14,
                                  ),
                                  onPressed: () => _action(
                                    'unstage',
                                    stagedFiles
                                        .map((f) => f['path'].toString())
                                        .toList(),
                                  ),
                                ),
                        ),
                        if (isStagedExpanded) ...[
                          if (stagedFiles.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Text(
                                strings.noStagedFiles,
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          else
                            for (final file in stagedFiles)
                              _buildGitFileRow(
                                file: file,
                                isStaged: true,
                                hasUnstagedEdit: file['unstaged'] == true,
                                tokens: tokens,
                                piTouchedPaths: piTouchedPaths,
                                manualSavedPaths: repository.manualSavedPaths,
                                blocked: blocked,
                                strings: strings,
                              ),
                        ],
                        _buildGitSectionHeader(
                          title: strings.changesSectionUpper,
                          count: unstagedFiles.length,
                          isExpanded: isUnstagedExpanded,
                          tokens: tokens,
                          onToggle: () {
                            ref
                                    .read(
                                      gitUnstagedExpandedProvider(
                                        widget.sessionId,
                                      ).notifier,
                                    )
                                    .state =
                                !isUnstagedExpanded;
                          },
                          trailing: unstagedFiles.isEmpty || blocked || _working
                              ? null
                              : IconButton(
                                  tooltip: strings.stageAllTooltip,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  icon: const Icon(Icons.add, size: 15),
                                  onPressed: () => _action(
                                    'stage',
                                    unstagedFiles
                                        .map((f) => f['path'].toString())
                                        .toList(),
                                  ),
                                ),
                        ),
                        if (isUnstagedExpanded) ...[
                          if (unstagedFiles.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Text(
                                strings.noUnstagedChanges,
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          else
                            for (final file in unstagedFiles)
                              _buildGitFileRow(
                                file: file,
                                isStaged: false,
                                hasUnstagedEdit: true,
                                tokens: tokens,
                                piTouchedPaths: piTouchedPaths,
                                manualSavedPaths: repository.manualSavedPaths,
                                blocked: blocked,
                                strings: strings,
                              ),
                        ],
                      ],
                    ),
            ),
            if (_working)
              LinearProgressIndicator(
                key: const ValueKey('git-working-progress'),
                minHeight: 2,
                color: tokens.accent,
                backgroundColor: tokens.surface,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  for (final (i, spec) in [
                    ('fetch', Icons.cloud_download_outlined, strings.gitFetchLabel, strings.gitFetchTooltip),
                    ('pull', Icons.arrow_downward, strings.gitPullLabel, strings.gitPullTooltip),
                    ('push', Icons.arrow_upward, strings.gitPushLabel, strings.gitPushTooltip),
                    ('sync', Icons.sync, strings.gitSyncLabel, strings.gitSyncTooltip),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(width: 4),
                    _remoteButton(
                      action: spec.$1,
                      icon: spec.$2,
                      label: spec.$3,
                      tooltip: spec.$4,
                      enabled: !blocked && !_working && !_loading,
                      tokens: tokens,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: blocked || _working || staged.isEmpty
                      ? null
                      : _commit,
                  child: Text(strings.commitButtonLabel(staged.length)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _paneHeader(
  BuildContext context,
  String title,
  IconData icon, {
  Widget? trailing,
  Widget? titleWidget,
  List<WorkspacePane>? companionTabs,
  WorkspacePane? activeCompanionTab,
  ValueChanged<WorkspacePane>? onSelectCompanionTab,
}) {
  final tokens = context.tokens;
  final hasTabs = companionTabs != null && companionTabs.length > 1;

  return Container(
    height: 38,
    margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: tokens.surfaceElevated,
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      border: Border.all(color: tokens.borderStrong),
    ),
    child: Row(
      children: [
        if (hasTabs)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tab in companionTabs) ...[
                    Builder(
                      builder: (context) {
                        final isActive = tab == activeCompanionTab;
                        final (tabTitle, tabIcon) = switch (tab) {
                          WorkspacePane.repository => (
                            'File',
                            Icons.folder_outlined,
                          ),
                          WorkspacePane.git => (
                            'Git Changes',
                            Icons.source_outlined,
                          ),
                          WorkspacePane.chat => (
                            'Chat',
                            Icons.chat_bubble_outline,
                          ),
                        };
                        return MouseRegion(
                          cursor: isActive
                              ? SystemMouseCursors.basic
                              : SystemMouseCursors.click,
                          child: GestureDetector(
                            key: ValueKey('companion-tab-${tab.name}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: isActive
                                ? null
                                : () => onSelectCompanionTab?.call(tab),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              padding: EdgeInsets.symmetric(
                                horizontal: isActive ? 10 : 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? tokens.surface
                                    : tokens.surface.withValues(alpha: 0),
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusSm,
                                ),
                                border: isActive
                                    ? Border.all(
                                        color: tokens.borderStrong,
                                        width: 1,
                                    )
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    tabIcon,
                                    size: isActive ? 14 : 13,
                                    color: isActive
                                        ? tokens.accent
                                        : tokens.textMuted,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    isActive
                                        ? tabTitle.toUpperCase()
                                        : tabTitle,
                                    style: TextStyle(
                                      color: isActive
                                          ? tokens.textPrimary
                                          : tokens.textMuted,
                                      fontSize: 11.5,
                                      fontFamily: tokens.uiFontFamily,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          )
        else if (titleWidget != null) ...[
          Expanded(child: titleWidget),
        ] else ...[
          Icon(icon, size: 16, color: tokens.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 11.5,
                fontFamily: tokens.uiFontFamily,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
        ?trailing,
      ],
    ),
  );
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
