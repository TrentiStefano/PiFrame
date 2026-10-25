import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RemovedReposNotifier extends StateNotifier<Set<String>> {
  RemovedReposNotifier() : super(const <String>{}) {
    _load();
  }

  File? _getStorageFile() {
    if (kIsWeb) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.piframe');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}/removed_repos.json');
    } catch (_) {
      return null;
    }
  }

  void _load() {
    final file = _getStorageFile();
    if (file != null && file.existsSync()) {
      try {
        final content = file.readAsStringSync();
        final list = (jsonDecode(content) as List?)?.cast<String>() ?? [];
        state = list.toSet();
      } catch (_) {}
    }
  }

  void _save() {
    final file = _getStorageFile();
    if (file != null) {
      try {
        file.writeAsStringSync(jsonEncode(state.toList()));
      } catch (_) {}
    }
  }

  void removeRepo(String repoPath) {
    if (!state.contains(repoPath)) {
      state = Set<String>.from(state)..add(repoPath);
      _save();
    }
  }

  void restoreRepo(String repoPath) {
    if (state.contains(repoPath)) {
      state = Set<String>.from(state)..remove(repoPath);
      _save();
    }
  }

  bool isRemoved(String repoPath) => state.contains(repoPath);
}

final removedReposProvider =
    StateNotifierProvider<RemovedReposNotifier, Set<String>>((ref) {
  return RemovedReposNotifier();
});
