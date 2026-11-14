import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_workspace.dart';

bool sessionWritesBlocked(SessionState session) =>
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
  RepositoryController(this.sessionId, this._readClient, [this._readStrings])
    : super(const RepositoryState());
  final String sessionId;
  final PcpClient? Function() _readClient;
  final AppStrings Function()? _readStrings;

  RepositoryState get currentState => state;

  Future<void> loadFiles() async {
    final client = _readClient();
    if (client == null) {
      state = RepositoryState(
        error:
            _readStrings?.call().daemonNotConnectedCapital ??
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
        error: error.toString(),
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
