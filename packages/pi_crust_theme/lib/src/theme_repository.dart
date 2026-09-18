import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'theme_spec.dart';

class ThemeRepository {
  final Map<String, ThemeSpec> _rawThemes = {};
  final Map<String, ThemeSpec> _resolvedThemes = {};
  String _activeThemeId = 'crust-dark';
  final _controller = StreamController<List<ThemeSpec>>.broadcast();
  StreamSubscription<FileSystemEvent>? _watcherSubscription;

  ThemeRepository() {
    _registerBuiltIns();
  }

  void _registerBuiltIns() {
    final darkBuiltIn = ThemeSpec(
      id: 'crust-dark',
      name: 'Crust Dark',
      author: 'Pi-Crust',
      version: '1.0.0',
      variant: 'dark',
    );
    final lightBuiltIn = ThemeSpec(
      id: 'crust-light',
      name: 'Crust Light',
      author: 'Pi-Crust',
      version: '1.0.0',
      variant: 'light',
    );
    _rawThemes['crust-dark'] = darkBuiltIn;
    _rawThemes['crust-light'] = lightBuiltIn;
    _resolveAll();
  }

  String get activeThemeId => _activeThemeId;
  ThemeSpec get activeTheme =>
      _resolvedThemes[_activeThemeId] ?? _resolvedThemes['crust-dark']!;

  List<ThemeSpec> get availableThemes => _resolvedThemes.values.toList();
  Stream<List<ThemeSpec>> watch() => _controller.stream;

  void setActiveTheme(String id) {
    if (_resolvedThemes.containsKey(id)) {
      _activeThemeId = id;
      _controller.add(availableThemes);
    }
  }

  void registerThemeJson(String jsonString) {
    try {
      final map = jsonDecode(jsonString);
      if (map is Map<String, dynamic>) {
        final spec = ThemeSpec.fromJson(map);
        _rawThemes[spec.id] = spec;
        _resolveAll();
      }
    } catch (e) {
      debugPrint('Error parsing theme JSON: $e');
    }
  }

  void registerTheme(ThemeSpec spec) {
    _rawThemes[spec.id] = spec;
    _resolveAll();
  }

  void _resolveAll() {
    _resolvedThemes.clear();
    for (final id in _rawThemes.keys) {
      _resolvedThemes[id] = _resolveTheme(id, <String>{}, 0);
    }
    _controller.add(availableThemes);
  }

  ThemeSpec _resolveTheme(String id, Set<String> visited, int depth) {
    final raw = _rawThemes[id];
    if (raw == null) {
      return _rawThemes['crust-dark']!;
    }

    if (raw.extendsTheme == null || raw.extendsTheme!.isEmpty) {
      return raw;
    }

    final parentId = raw.extendsTheme!;
    if (visited.contains(parentId) || depth >= 3) {
      // Cycle or depth limit exceeded
      raw.diagnostics.add(
          'Inheritance cycle or max depth exceeded for theme "$id" extending "$parentId". Aborting inheritance.');
      return raw;
    }

    visited.add(id);
    final parentResolved = _resolveTheme(parentId, visited, depth + 1);
    return ThemeSpec.merge(parentResolved, raw);
  }

  void watchDirectory(Directory dir) {
    if (!dir.existsSync()) return;
    try {
      _watcherSubscription?.cancel();
      _watcherSubscription = dir.watch().listen((event) {
        if (event.path.endsWith('.json')) {
          _reloadFromDirectory(dir);
        }
      });
    } catch (e) {
      debugPrint('ThemeDirectory watcher error: $e');
    }
  }

  void _reloadFromDirectory(Directory dir) {
    try {
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
      for (final file in files) {
        final content = file.readAsStringSync();
        registerThemeJson(content);
      }
    } catch (e) {
      debugPrint('Failed to reload themes from directory: $e');
    }
  }

  void dispose() {
    _watcherSubscription?.cancel();
    _controller.close();
  }
}
