import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/platform/user_data_service.dart';

const _fileName = 'pinned_sessions.json';

class PinnedSessionsNotifier extends StateNotifier<List<String>> {
  // Saved through [_storage] only when built without an explicit list. A notifier
  // built from a list is in memory only: tests must never rewrite the user's real pins.
  final UserDataService? _storage;

  PinnedSessionsNotifier([Iterable<String>? initial, UserDataService? storage])
    : _storage = initial == null ? storage : null,
      super(initial != null ? initial.toList() : const <String>[]) {
    if (initial == null) {
      _load();
    }
  }

  /// True when pins are saved to the user's data folder.
  bool get persists => _storage != null;

  void _load() {
    final content = _storage?.read(_fileName);
    if (content == null) return;
    try {
      final list = (jsonDecode(content) as List?)?.cast<String>() ?? [];
      final seen = <String>{};
      final ordered = <String>[];
      for (final id in list) {
        if (seen.add(id)) {
          ordered.add(id);
        }
      }
      state = ordered;
    } catch (_) {}
  }

  void _save() {
    final storage = _storage;
    if (storage == null) return;
    try {
      storage.write(_fileName, jsonEncode(state));
    } catch (_) {}
  }

  void togglePin(String sessionId) {
    if (state.contains(sessionId)) {
      state = List<String>.from(state)..remove(sessionId);
    } else {
      state = List<String>.from(state)..add(sessionId);
    }
    _save();
  }

  void unpin(String sessionId) {
    if (state.contains(sessionId)) {
      state = List<String>.from(state)..remove(sessionId);
      _save();
    }
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length || newIndex < 0) return;
    final list = List<String>.from(state);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex >= list.length) newIndex = list.length - 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = list;
    _save();
  }

  void reorderById(String movedId, int targetIndexInPinned) {
    final list = List<String>.from(state);
    final oldIndex = list.indexOf(movedId);
    if (oldIndex < 0) return;
    list.removeAt(oldIndex);
    final clampedIndex = targetIndexInPinned.clamp(0, list.length);
    list.insert(clampedIndex, movedId);
    state = list;
    _save();
  }

  bool isPinned(String sessionId) => state.contains(sessionId);
}

final pinnedSessionsProvider = StateNotifierProvider<PinnedSessionsNotifier, List<String>>((ref) {
  return PinnedSessionsNotifier(null, ref.read(userDataServiceProvider));
});
