import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../domain/session/agent_status.dart';

/// Whether the "Review Changes" layout mode is currently active.
final isReviewingChangesProvider = StateProvider<bool>((ref) => false);

/// Diff view display mode: single unified column vs two split columns.
enum DiffViewMode {
  singleColumn,
  twoColumn,
}

final diffViewModeProvider = StateProvider<DiffViewMode>(
  (ref) => DiffViewMode.singleColumn,
);

/// Set of file paths currently expanded in the Review Changes pane.
final expandedReviewFilesProvider =
    StateProvider.family<Set<String>, String>((ref, sessionId) => {});

/// Represents a single file that has been modified.
class SessionChangedFile {
  final String path;
  final String filename;
  final String directory;
  final int additions;
  final int deletions;
  final String status;
  final String? diff;
  final bool isLoadingDiff;

  const SessionChangedFile({
    required this.path,
    required this.filename,
    required this.directory,
    required this.additions,
    required this.deletions,
    this.status = 'modified',
    this.diff,
    this.isLoadingDiff = false,
  });

  SessionChangedFile copyWith({
    String? path,
    String? filename,
    String? directory,
    int? additions,
    int? deletions,
    String? status,
    String? diff,
    bool? isLoadingDiff,
  }) =>
      SessionChangedFile(
        path: path ?? this.path,
        filename: filename ?? this.filename,
        directory: directory ?? this.directory,
        additions: additions ?? this.additions,
        deletions: deletions ?? this.deletions,
        status: status ?? this.status,
        diff: diff ?? this.diff,
        isLoadingDiff: isLoadingDiff ?? this.isLoadingDiff,
      );
}

/// State of the session changed files.
class SessionChangesState {
  final bool isLoading;
  final List<SessionChangedFile> files;
  final int totalAdditions;
  final int totalDeletions;
  final String? error;

  const SessionChangesState({
    this.isLoading = false,
    this.files = const [],
    this.totalAdditions = 0,
    this.totalDeletions = 0,
    this.error,
  });

  SessionChangesState copyWith({
    bool? isLoading,
    List<SessionChangedFile>? files,
    int? totalAdditions,
    int? totalDeletions,
    String? error,
  }) =>
      SessionChangesState(
        isLoading: isLoading ?? this.isLoading,
        files: files ?? this.files,
        totalAdditions: totalAdditions ?? this.totalAdditions,
        totalDeletions: totalDeletions ?? this.totalDeletions,
        error: error,
      );
}

class SessionChangesNotifier extends StateNotifier<SessionChangesState> {
  final Ref ref;
  final String sessionId;

  SessionChangesNotifier(this.ref, this.sessionId)
      : super(const SessionChangesState()) {
    refresh();
  }

  static String _extractFileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.substring(idx + 1) : normalized;
  }

  static String _extractDirectory(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.substring(0, idx) : '';
  }

  Future<void> refresh() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      state = state.copyWith(
        isLoading: false,
        files: const [],
        totalAdditions: 0,
        totalDeletions: 0,
        error: 'Daemon non connesso',
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await client.refreshWorkspace(sessionId);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final rawFiles = (data['files'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final fileMap = <String, SessionChangedFile>{};
      int totalAdd = 0;
      int totalDel = 0;

      for (final f in rawFiles) {
        final path = f['path']?.toString() ?? '';
        if (path.isEmpty) continue;
        final add = (f['additions'] as num?)?.toInt() ?? 0;
        final del = (f['deletions'] as num?)?.toInt() ?? 0;
        totalAdd += add;
        totalDel += del;

        fileMap[path] = SessionChangedFile(
          path: path,
          filename: _extractFileName(path),
          directory: _extractDirectory(path),
          additions: add,
          deletions: del,
          status: f['status'] == 'untracked'
              ? 'added'
              : (f['status']?.toString() ?? 'modified'),
        );
      }

      final list = fileMap.values.toList()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

      state = state.copyWith(
        isLoading: false,
        files: list,
        totalAdditions: totalAdd,
        totalDeletions: totalDel,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        files: const [],
        totalAdditions: 0,
        totalDeletions: 0,
        error: e.toString(),
      );
    }
  }

  Future<void> fetchFileDiff(String filePath) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;

    final existingIndex = state.files.indexWhere((f) => f.path == filePath);
    if (existingIndex < 0) return;

    final existing = state.files[existingIndex];
    if (existing.diff != null && existing.diff!.isNotEmpty) return;

    final updated = List<SessionChangedFile>.from(state.files);
    updated[existingIndex] = existing.copyWith(isLoadingDiff: true);
    state = state.copyWith(files: updated);

    try {
      final res = await client.getWorkspaceDiff(sessionId, filePath: filePath);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final diffText = data['diff']?.toString() ?? '';

      final finalFiles = List<SessionChangedFile>.from(state.files);
      final finalIdx = finalFiles.indexWhere((f) => f.path == filePath);
      if (finalIdx >= 0) {
        finalFiles[finalIdx] = finalFiles[finalIdx].copyWith(
          diff: diffText,
          isLoadingDiff: false,
        );
        state = state.copyWith(files: finalFiles);
      }
    } catch (_) {
      final finalFiles = List<SessionChangedFile>.from(state.files);
      final finalIdx = finalFiles.indexWhere((f) => f.path == filePath);
      if (finalIdx >= 0) {
        finalFiles[finalIdx] = finalFiles[finalIdx].copyWith(
          isLoadingDiff: false,
          diff: 'Impossibile caricare il diff del file.',
        );
        state = state.copyWith(files: finalFiles);
      }
    }
  }
}

final sessionChangesProvider = StateNotifierProvider.family<
    SessionChangesNotifier, SessionChangesState, String>((ref, sessionId) {
  return SessionChangesNotifier(ref, sessionId);
});

/// Indicates whether the session has modified files and the agent is settled.
final sessionHasModifiedFilesProvider =
    Provider.family<bool, String>((ref, sessionId) {
  final isSettled = ref.watch(sessionStateFamily(sessionId).select((session) =>
      !session.isStreaming &&
      session.agentStatus != AgentStatus.working &&
      session.agentStatus != AgentStatus.retrying &&
      session.agentStatus != AgentStatus.compacting));

  if (!isSettled) return false;

  final changes = ref.watch(sessionChangesProvider(sessionId));
  return changes.files.isNotEmpty;
});
