import '../../domain/session/session_labels.dart';

/// True for worker and subagent sessions, which the rail and the welcome hide.
bool isSubsessionEntry(Map<String, dynamic> session) {
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

int sessionActivityTimestamp(Map<String, dynamic> s) {
  final raw = s['updatedAt'] ?? s['mtime'] ?? s['createdAt'] ?? s['ts'];
  if (raw is num) return raw.toInt();
  if (raw is String) {
    final parsedNum = int.tryParse(raw);
    if (parsedNum != null) return parsedNum;
    final parsedDate = DateTime.tryParse(raw);
    if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;
  }
  return 0;
}

/// Top-level sessions, most recently active first.
List<Map<String, dynamic>> resumableSessions(List<Map<String, dynamic>> sessions) {
  final result = sessions.where((s) => !isSubsessionEntry(s)).toList();
  result.sort((a, b) => sessionActivityTimestamp(b).compareTo(sessionActivityTimestamp(a)));
  return result;
}

/// Distinct repository folders of [sessions], most recently active first.
List<String> recentSessionFolders(List<Map<String, dynamic>> sessions, {int limit = 5}) {
  final folders = <String>[];
  for (final session in resumableSessions(sessions)) {
    final folder = sessionFolder(session).trim();
    if (folder.isEmpty || folders.contains(folder)) continue;
    folders.add(folder);
    if (folders.length == limit) break;
  }
  return folders;
}
