import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PinnedSessionsNotifier extends StateNotifier<List<String>> {
  PinnedSessionsNotifier([Iterable<String>? initial])
      : super(initial != null ? initial.toList() : const <String>[]) {
    if (initial == null) {
      _load();
    }
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
      return File('${dir.path}/pinned_sessions.json');
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
  }

  void _save() {
    final file = _getStorageFile();
    if (file != null) {
      try {
        file.writeAsStringSync(jsonEncode(state));
      } catch (_) {}
    }
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

final pinnedSessionsProvider =
    StateNotifierProvider<PinnedSessionsNotifier, List<String>>((ref) {
  return PinnedSessionsNotifier();
});
