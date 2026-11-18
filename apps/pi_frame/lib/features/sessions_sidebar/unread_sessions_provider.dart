import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/platform/widget_test_binding.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';

/// Whether a session's own agent is answering (not background subagents).
bool agentAtWork(SessionState s) =>
    s.agentStatus == AgentStatus.working ||
    s.agentStatus == AgentStatus.retrying ||
    s.agentStatus == AgentStatus.compacting ||
    s.isStreaming ||
    s.activeToolCalls.isNotEmpty;

/// Sessions with agent activity the user has not opened yet: the sessions
/// rail lights their notification dot. Opening a session marks it read.
///
/// The set is saved in `~/.piframe/unread_sessions.json`, so an answer that
/// arrived before a restart is still flagged after it.
class UnreadSessionsNotifier extends StateNotifier<Set<String>> {
  // Built from an explicit set (tests), or under a test binding, the notifier
  // never touches the user's real file.
  final bool _persists;

  /// Last `lastActivityAt` seen per session in the daemon's listing.
  final Map<String, num> _lastActivity = {};

  /// Sessions opened during this run. Their state stays subscribed, so the
  /// rail can show them working, and their answers light the dot at once.
  final Set<String> _followed = {};

  void Function(String sessionId)? _follow;

  bool isFollowed(String sessionId) => _followed.contains(sessionId);

  /// Starts watching a session's live state for finished answers.
  void follow(String sessionId) => _follow?.call(sessionId);

  UnreadSessionsNotifier([Iterable<String>? initial])
      : _persists = initial == null && !kIsWeb && !isWidgetTestBinding,
        super(initial?.toSet() ?? const <String>{}) {
    if (_persists) _load();
  }

  File? _storageFile() {
    if (!_persists) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.piframe');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}/unread_sessions.json');
    } catch (_) {
      return null;
    }
  }

  void _load() {
    final file = _storageFile();
    if (file == null || !file.existsSync()) return;
    try {
      final list = (jsonDecode(file.readAsStringSync()) as List?) ?? const [];
      state = {for (final id in list) if (id is String) id};
    } catch (_) {}
  }

  void _save() {
    final file = _storageFile();
    if (file == null) return;
    try {
      file.writeAsStringSync(jsonEncode(state.toList()));
    } catch (_) {}
  }

  void markUnread(String sessionId) {
    if (sessionId.isEmpty || state.contains(sessionId)) return;
    state = {...state, sessionId};
    _save();
  }

  void markRead(String sessionId) {
    if (!state.contains(sessionId)) return;
    state = {...state}..remove(sessionId);
    _save();
  }

  /// Compares a daemon listing with the previous one: a session whose
  /// activity advanced while it was not the open session gets unread. The
  /// first listing only sets the baseline, and sessions no longer listed are
  /// forgotten.
  void noteListing(List<Map<String, dynamic>> sessions, {String? activeId}) {
    final ids = <String>{};
    for (final session in sessions) {
      final id = session['id'];
      final activity = session['lastActivityAt'];
      if (id is! String || id.isEmpty) continue;
      ids.add(id);
      if (activity is! num) continue;
      final previous = _lastActivity[id];
      _lastActivity[id] = activity;
      // A session that first appears now (a new one) is not flagged.
      if (id == activeId || previous == null) continue;
      if (activity > previous) markUnread(id);
    }
    final gone = state.where((id) => !ids.contains(id)).toList();
    if (sessions.isNotEmpty && gone.isNotEmpty) {
      state = {...state}..removeAll(gone);
      _save();
    }
  }
}

final unreadSessionsProvider =
    StateNotifierProvider<UnreadSessionsNotifier, Set<String>>((ref) {
  final notifier = UnreadSessionsNotifier();

  // An answer that lands while another session is open marks it unread. The
  // daemon listing alone is not enough: its activity time lags a running turn.
  void follow(String id) {
    if (id.isEmpty || !notifier._followed.add(id)) return;
    ref.listen<bool>(sessionStateFamily(id).select(agentAtWork), (was, now) {
      if (was == true && !now && ref.read(activeSessionIdProvider) != id) {
        notifier.markUnread(id);
      }
    });
  }

  ref.listen<AsyncValue<List<Map<String, dynamic>>>>(
    sessionListProvider,
    (_, next) {
      final sessions = next.value;
      if (sessions == null) return;
      notifier.noteListing(
        sessions,
        activeId: ref.read(activeSessionIdProvider),
      );
    },
    fireImmediately: true,
  );
  ref.listen<String?>(activeSessionIdProvider, (_, id) {
    if (id == null) return;
    notifier.markRead(id);
    follow(id);
  }, fireImmediately: true);
  notifier._follow = follow;
  return notifier;
});
