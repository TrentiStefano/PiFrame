import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/platform/user_data_service.dart';

const _fileName = 'removed_repos.json';

class RemovedReposNotifier extends StateNotifier<Set<String>> {
  final UserDataService? _storage;

  RemovedReposNotifier([UserDataService? storage]) : _storage = storage, super(const <String>{}) {
    _load();
  }

  void _load() {
    final content = _storage?.read(_fileName);
    if (content == null) return;
    try {
      final list = (jsonDecode(content) as List?)?.cast<String>() ?? [];
      state = list.toSet();
    } catch (_) {}
  }

  void _save() {
    final storage = _storage;
    if (storage == null) return;
    try {
      storage.write(_fileName, jsonEncode(state.toList()));
    } catch (_) {}
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
}

final removedReposProvider = StateNotifierProvider<RemovedReposNotifier, Set<String>>((ref) {
  return RemovedReposNotifier(ref.read(userDataServiceProvider));
});
