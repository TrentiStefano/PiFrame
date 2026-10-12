import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PinnedSessionsNotifier extends StateNotifier<Set<String>> {
  PinnedSessionsNotifier() : super(const <String>{}) {
    _load();
  }

  File? _getStorageFile() {
    if (kIsWeb) return null;
    try {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
      final dir = Directory('$home/.pi-crust');
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

  void togglePin(String sessionId) {
    if (state.contains(sessionId)) {
      state = Set<String>.from(state)..remove(sessionId);
    } else {
      state = Set<String>.from(state)..add(sessionId);
    }
    _save();
  }

  bool isPinned(String sessionId) => state.contains(sessionId);
}

final pinnedSessionsProvider =
    StateNotifierProvider<PinnedSessionsNotifier, Set<String>>((ref) {
  return PinnedSessionsNotifier();
});
