import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';
import '../composer/composer_draft.dart';
import '../../ui/code/diff_block.dart';

enum WorkspacePane { chat, repository, git }

String _repositoryLoadError(Object error) {
  final message = error.toString();
  if (message.contains('Unsupported command type: workspace.listFiles')) {
    return 'Daemon obsoleto: esegui `pnpm run build:agentd`, ricostruisci Pi-Crust e riavvia il daemon solo quando nessun worker Pi è attivo.';
  }
  return message;
}

Set<String> _piTouchedPaths(SessionState session) {
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

bool _pathSetContains(Set<String> paths, String path) =>
    paths.contains(path) ||
    paths.any((value) => value.toLowerCase() == path.toLowerCase());

String _changeOriginLabel(
  String path,
  Set<String> piTouchedPaths,
  Set<String> manualSavedPaths,
) {
  final touchedByPi = _pathSetContains(piTouchedPaths, path);
  final savedHere = _pathSetContains(manualSavedPaths, path);
  if (touchedByPi && savedHere) return 'Tool Pi + salvataggio Pi-Crust';
  if (touchedByPi) return 'Tool Pi ha scritto il percorso';
  if (savedHere) return 'Salvato da te in Pi-Crust';
  return 'Origine non determinata';
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
        );
      },
    );

class RepositoryController extends StateNotifier<RepositoryState> {
  RepositoryController(this.sessionId, this._readClient)
    : super(const RepositoryState());
  final String sessionId;
  final PcpClient? Function() _readClient;

  RepositoryState get currentState => state;

  Future<void> loadFiles() async {
    final client = _readClient();
    if (client == null) {
      state = const RepositoryState(error: 'Daemon non connesso');
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
      final data = result['data'] as Map<String, dynamic>;
      final files = (data['files'] as List).cast<Map<String, dynamic>>();
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
        error: _repositoryLoadError(error),
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
      final data = result['data'] as Map<String, dynamic>;
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
    if (client == null || buffer == null)
      throw StateError('File non disponibile');
    final content = buffer.content;
    final result = await client.saveWorkspaceFile(sessionId, {
      'path': path,
      'content': content,
      'revision': revisionOverride ?? buffer.revision,
    });
    final data = result['data'] as Map<String, dynamic>;
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
    final data = result['data'] as Map<String, dynamic>;
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
  if (!await resolveDirtyRepository(context, ref, currentId)) return false;
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
  final writesBlocked = _sessionWritesBlocked(session);
  final canSave = !writesBlocked && ref.read(pcpClientProvider) != null;
  final blockedReason = session.readOnly
      ? (session.readOnlyReason ?? 'sessione in sola lettura')
      : writesBlocked
      ? session.agentStatus.label
      : 'daemon non connesso';
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: tokens.surface,
      title: const Text('Modifiche non salvate'),
      content: Text(
        canSave
            ? 'Salva o scarta le modifiche prima di lasciare questa sessione.'
            : 'Salvataggio non disponibile: $blockedReason. Puoi scartare le modifiche o annullare.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'cancel'),
          child: const Text('Annulla'),
        ),
        if (canSave)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('Scarta'),
          ),
        if (!canSave)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('Scarta'),
          ),
        if (canSave)
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Salva'),
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
          controller.currentState.buffers[entry.key]?.dirty == true)
        return false;
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
  if (_sessionWritesBlocked(session)) {
    throw StateError(
      session.readOnly
          ? (session.readOnlyReason ?? 'Sessione in sola lettura')
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
        !message.contains('reload before saving'))
      rethrow;
    final disk = await controller.currentDisk(path);
    if (!context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('File modificato altrove'),
        content: Text(
          '$path è cambiato su disco. Il testo locale resta intatto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'keep'),
            child: const Text('Mantieni modifiche'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'reload'),
            child: const Text('Ricarica disco'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'overwrite'),
            child: const Text('Sovrascrivi esplicitamente'),
          ),
        ],
      ),
    );
    if (choice == 'reload')
      controller.reload(path, disk.content, disk.revision);
    if (choice == 'overwrite')
      await controller.save(path, revisionOverride: disk.revision);
    if (choice == 'keep') rethrow;
  }
}

class RepositoryPane extends ConsumerStatefulWidget {
  const RepositoryPane({super.key, required this.sessionId});
  final String sessionId;
  @override
  ConsumerState<RepositoryPane> createState() => _RepositoryPaneState();
}

class _RepositoryPaneState extends ConsumerState<RepositoryPane> {
  final _editor = TextEditingController();
  String? _editorPath;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        ref
            .read(repositoryStateProvider(widget.sessionId).notifier)
            .loadFiles();
    });
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Widget _fileList(
    CrustTokens tokens,
    RepositoryState repo,
    String? selectedPath,
  ) {
    if (repo.loading && repo.files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (repo.files.isEmpty) {
      return Center(
        child: Text(
          repo.error ?? 'Nessun file disponibile.',
          style: TextStyle(
            color: repo.error == null ? tokens.textMuted : tokens.danger,
          ),
        ),
      );
    }
    return ListView.builder(
      key: PageStorageKey<String>('repository-files-${widget.sessionId}'),
      itemCount: repo.files.length,
      itemBuilder: (context, index) {
        final filePath = repo.files[index]['path'].toString();
        final segments = filePath.split('/');
        final parent = segments.length > 1
            ? segments.take(segments.length - 1).join('/')
            : null;
        final selected = filePath == selectedPath;
        return Material(
          color: tokens.surface.withValues(alpha: 0),
          child: Tooltip(
            message: filePath,
            child: ListTile(
              dense: true,
              selected: selected,
              selectedTileColor: tokens.surfaceElevated,
              contentPadding: EdgeInsets.only(
                left: 8 + (segments.length - 1) * 12,
                right: 8,
              ),
              leading: Icon(
                Icons.description_outlined,
                size: 16,
                color: selected ? tokens.accent : tokens.textMuted,
              ),
              title: Text(
                segments.last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12,
                  fontFamily: tokens.monoFontFamily,
                ),
              ),
              subtitle: parent == null
                  ? null
                  : Text(
                      parent,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.textMuted, fontSize: 10),
                    ),
              onTap: () => ref
                  .read(repositoryStateProvider(widget.sessionId).notifier)
                  .selectFile(filePath),
            ),
          ),
        );
      },
    );
  }

  Widget _editorPane(
    BuildContext context,
    CrustTokens tokens,
    RepositoryState repo,
    SessionState session,
    String? path,
    WorkspaceFileBuffer? buffer,
    bool writeBlocked,
    String? blockReason, {
    required bool compact,
  }) {
    if (path == null) {
      return Center(
        child: Text(
          'Seleziona un file',
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }
    if (buffer == null) {
      return Center(
        child: Text(
          repo.error ?? 'Caricamento file...',
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
                  tooltip: 'Torna ai file',
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
                    'MODIFICATO',
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Salvataggio non riuscito: $error',
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: const Text('Salva'),
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
          child: TextField(
            key: ValueKey('repository-editor-${widget.sessionId}'),
            controller: _editor,
            enabled: !session.readOnly,
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
                    label: 'Aggiungi alla chat',
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
              hintText: writeBlocked ? 'Sola lettura' : 'Contenuto file',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final repo = ref.watch(repositoryStateProvider(widget.sessionId));
    final session = ref.watch(sessionStateFamily(widget.sessionId));
    final path = repo.selectedPath;
    final buffer = path == null ? null : repo.buffers[path];
    if (path != _editorPath) {
      _editorPath = path;
      _editor.value = TextEditingValue(text: buffer?.content ?? '');
    } else if (buffer != null && _editor.text != buffer.content) {
      _editor.value = TextEditingValue(
        text: buffer.content,
        selection: TextSelection.collapsed(offset: buffer.content.length),
      );
    }
    final writeBlocked = _sessionWritesBlocked(session);
    final blockReason = session.readOnly
        ? (session.readOnlyReason ?? 'Sessione in sola lettura')
        : writeBlocked
        ? 'Salvataggio disabilitato: ${session.agentStatus.label}.'
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
            trailing: IconButton(
              tooltip: 'Aggiorna file',
              onPressed: repo.loading
                  ? null
                  : () => ref
                        .read(
                          repositoryStateProvider(widget.sessionId).notifier,
                        )
                        .loadFiles(),
              icon: const Icon(Icons.refresh, size: 17),
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
                final compactFiles = constraints.maxWidth < 420;
                final treeWidth = compactFiles
                    ? constraints.maxWidth
                    : (constraints.maxWidth * 0.32)
                          .clamp(140.0, 220.0)
                          .toDouble();
                return Row(
                  children: [
                    if (!compactFiles || path == null)
                      SizedBox(
                        width: treeWidth,
                        child: _fileList(tokens, repo, path),
                      ),
                    if (!compactFiles)
                      VerticalDivider(width: 1, color: tokens.borderStrong),
                    if (!compactFiles || path != null)
                      Expanded(
                        child: _editorPane(
                          context,
                          tokens,
                          repo,
                          session,
                          path,
                          buffer,
                          writeBlocked,
                          blockReason,
                          compact: compactFiles,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (repo.truncated)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Elenco file limitato dal daemon.',
                style: TextStyle(color: tokens.textMuted, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

class GitChangesPane extends ConsumerStatefulWidget {
  const GitChangesPane({super.key, required this.sessionId});
  final String sessionId;
  @override
  ConsumerState<GitChangesPane> createState() => _GitChangesPaneState();
}

class _GitChangesPaneState extends ConsumerState<GitChangesPane> {
  Map<String, dynamic>? _status;
  bool _loading = false;
  bool _working = false;
  final _message = TextEditingController();
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(pcpClientProvider)!
          .refreshWorkspace(widget.sessionId);
      if (mounted)
        setState(() => _status = result['data'] as Map<String, dynamic>?);
    } catch (e) {
      if (mounted) setState(() => _status = {'error': e.toString()});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _files =>
      ((_status?['files'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .where((file) => file['status'] != 'untracked')
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
    if (_working || paths.isEmpty) return;
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Operazione Git non riuscita: $error')),
        );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showDiff(String path) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      final result = await client.getWorkspaceDiff(
        widget.sessionId,
        filePath: path,
      );
      final diff = result['data']?['diff']?.toString() ?? '';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
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
                        tooltip: 'Chiudi diff',
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
                            ? 'Nessuna differenza trovata.'
                            : diff,
                        filename: path,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Diff non disponibile: $error')));
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
      diff = result['data']?['diff']?.toString() ?? '';
    } catch (_) {}
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annullare tutte le modifiche?'),
        content: SizedBox(
          width: 640,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$path\n${_status?['rootPath'] ?? '—'} · ${_status?['branch'] ?? '—'}',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: DiffBlock(
                    diffText: diff.isEmpty ? 'Diff non disponibile.' : diff,
                    filename: path,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('L’operazione rimuove modifiche staged e unstaged.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Annulla modifiche'),
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
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Commit dei file staged'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Repository: ${_status?['rootPath'] ?? '—'} · ramo: ${_status?['branch'] ?? '—'}\nFile revisionati: ${staged.join(', ')}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Messaggio commit'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _message.text.trim()),
            child: const Text('Commit'),
          ),
        ],
      ),
    );
    if (message == null || message.isEmpty) return;
    _message.clear();
    await _action('commit', staged, message: message, expected: staged);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final session = ref.watch(sessionStateFamily(widget.sessionId));
    final repository = ref.watch(repositoryStateProvider(widget.sessionId));
    final piTouchedPaths = _piTouchedPaths(session);
    final blocked = _sessionWritesBlocked(session);
    final files = _files;
    final staged = _staged.toSet();
    final repo = _status?['isRepository'] == true;
    final root = _status?['rootPath']?.toString() ?? session.cwd;
    return Container(
      decoration: BoxDecoration(color: tokens.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _paneHeader(
            context,
            'Git Changes',
            Icons.source_outlined,
            trailing: IconButton(
              tooltip: 'Aggiorna stato Git',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 17),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text(
              '$root · ${_status?['branch'] ?? '—'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontFamily: tokens.monoFontFamily,
              ),
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
                  session.readOnly
                      ? 'Scritture disabilitate: ${session.readOnlyReason ?? 'sessione in sola lettura'}'
                      : 'Scritture disabilitate mentre Pi sta lavorando.',
                  style: TextStyle(color: tokens.textPrimary, fontSize: 11),
                ),
              ),
            ),
          if (!repo)
            Expanded(
              child: Center(
                child: Text(
                  _loading
                      ? 'Caricamento...'
                      : (_status?['error']?.toString() ??
                            'Nessun repository Git.'),
                  style: TextStyle(
                    color: _status?['error'] == null
                        ? tokens.textMuted
                        : tokens.danger,
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 4,
                children: [
                  Text(
                    '${files.length} file',
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
                        'Working tree pulito',
                        style: TextStyle(color: tokens.textMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final file = files[index];
                        final path = file['path'].toString();
                        final isStaged = staged.contains(path);
                        final hasUnstagedEdit = file['unstaged'] == true;
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
                            contentPadding: const EdgeInsets.only(
                              left: 8,
                              right: 2,
                            ),
                            onTap: () => _showDiff(path),
                            leading: Icon(
                              Icons.description_outlined,
                              size: 16,
                              color: isStaged
                                  ? tokens.accent
                                  : tokens.textMuted,
                            ),
                            title: Text(
                              path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 11,
                                fontFamily: tokens.monoFontFamily,
                              ),
                            ),
                            subtitle: Text(
                              '${file['status'] ?? 'modified'} · $stateLabel · ${_changeOriginLabel(path, piTouchedPaths, repository.manualSavedPaths)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isStaged
                                    ? tokens.accent
                                    : tokens.textMuted,
                                fontSize: 9,
                              ),
                            ),
                            trailing: SizedBox(
                              width: 88,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (hasUnstagedEdit)
                                    IconButton(
                                      tooltip: 'Metti in stage $path',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      onPressed: blocked || _working
                                          ? null
                                          : () => _action('stage', [path]),
                                      icon: const Icon(Icons.add, size: 17),
                                    )
                                  else if (isStaged)
                                    IconButton(
                                      tooltip: 'Togli dallo stage $path',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      onPressed: blocked || _working
                                          ? null
                                          : () => _action('unstage', [path]),
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 16,
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: 'Annulla modifiche a $path',
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
                      },
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
                  child: Text('Commit (${staged.length})'),
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
}) {
  final tokens = context.tokens;
  return Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: tokens.displaySurface,
      border: Border(bottom: BorderSide(color: tokens.borderStrong)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16, color: tokens.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: tokens.displayText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .6,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
