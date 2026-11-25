import '../../domain/session/session_state.dart';

Set<String> piTouchedPaths(SessionState session) {
  final paths = <String>{};
  final tools = [...session.entries.expand((entry) => entry.toolCalls), ...session.activeToolCalls.values];
  for (final tool in tools) {
    if (!const {'write', 'edit'}.contains(tool.toolName.toLowerCase()) || tool.isError) {
      continue;
    }
    final rawPath = tool.args['path']?.toString();
    if (rawPath == null || rawPath.isEmpty) continue;
    final candidate = rawPath.replaceAll('\\', '/');
    final root = session.cwd.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');
    final rootPrefix = '$root/';
    if (candidate.toLowerCase().startsWith(rootPrefix.toLowerCase())) {
      paths.add(candidate.substring(rootPrefix.length));
    } else if (!candidate.startsWith('/') && !RegExp(r'^[a-zA-Z]:').hasMatch(candidate)) {
      paths.add(candidate.replaceFirst(RegExp(r'^\./'), ''));
    }
  }
  return paths;
}
