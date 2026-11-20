import 'package:path/path.dart' as p;

String sessionFolder(Map<String, dynamic> session) {
  final gitRoot = (session['gitRoot'] ?? '').toString().trim();
  return gitRoot.isNotEmpty ? gitRoot : (session['cwd'] ?? '').toString();
}

bool _isWindowsPath(String path) =>
    path.contains('\\') ||
    path.startsWith('//') ||
    RegExp(r'^[A-Za-z]:').hasMatch(path);

String _normalizedPath(String path) => _isWindowsPath(path)
    ? p.windows.normalize(path.trim().replaceAll('/', '\\'))
    : p.posix.normalize(path.trim());

String _pathKey(String path) {
  final normalized = _normalizedPath(path).replaceAll('\\', '/');
  return _isWindowsPath(path) ? normalized.toLowerCase() : normalized;
}

List<String> _pathSegments(String path) => path.trim().isEmpty
    ? const []
    : _normalizedPath(path)
          .replaceAll('\\', '/')
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList();

String _nameKey(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

Map<String, String> folderDisplayNames(Iterable<String> folders) {
  final segments = {
    for (final folder in folders) folder: _pathSegments(folder),
  };
  final depths = {for (final folder in segments.keys) folder: 1};

  while (true) {
    final labels = <String, String>{};
    final collisions = <String, List<String>>{};
    for (final entry in segments.entries) {
      final parts = entry.value;
      final depth = depths[entry.key]!;
      final label = parts.isEmpty
          ? (entry.key.trim().isEmpty ? 'Sessioni' : entry.key)
          : parts
                .skip((parts.length - depth).clamp(0, parts.length))
                .join(' / ');
      labels[entry.key] = label;
      collisions.putIfAbsent(_nameKey(label), () => []).add(entry.key);
    }

    var changed = false;
    for (final group in collisions.values) {
      if (group.map(_pathKey).toSet().length < 2) continue;
      for (final folder in group) {
        if (depths[folder]! < segments[folder]!.length) {
          depths[folder] = depths[folder]! + 1;
          changed = true;
        }
      }
    }
    if (!changed) return labels;
  }
}

Map<String, String> sessionDisplayNames(
  Iterable<Map<String, dynamic>> sessions,
) {
  final labels = <String, String>{};
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final session in sessions) {
    final id = (session['id'] ?? '').toString();
    final name = (session['name'] ?? id).toString();
    labels[id] = name;
    groups.putIfAbsent(_nameKey(name), () => []).add(session);
  }

  String workingFolder(Map<String, dynamic> session) {
    final cwd = (session['cwd'] ?? '').toString().trim();
    return cwd.isNotEmpty ? cwd : sessionFolder(session);
  }

  for (final group in groups.values) {
    final folders = group
        .map(workingFolder)
        .where((folder) => folder.isNotEmpty);
    if (folders.map(_pathKey).toSet().length < 2) continue;
    final folderLabels = folderDisplayNames(folders);
    for (final session in group) {
      final folder = workingFolder(session);
      if (folder.isEmpty) continue;
      final id = (session['id'] ?? '').toString();
      final name = labels[id]!;
      final parts = _pathSegments(folder);
      final folderLabel = folderLabels[folder]!;
      labels[id] = parts.isNotEmpty && _nameKey(name) == _nameKey(parts.last)
          ? folderLabel
          : '$name · $folderLabel';
    }
  }
  return labels;
}
