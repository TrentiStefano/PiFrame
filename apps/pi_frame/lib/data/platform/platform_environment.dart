import 'dart:io';

import 'package:flutter/foundation.dart';

/// Centralized utility for resolving system environments, augmented PATHs,
/// and CLI executables across macOS, Linux, and Windows.
///
/// On macOS, GUI apps launched from Finder/Dock/Launch Services inherit a
/// minimal launchd PATH (`/usr/bin:/bin:/usr/sbin:/sbin`). CLI tools installed
/// via Homebrew, curl, npm, or Pi's official installer reside in locations
/// like `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`.
/// [PlatformEnvironment] ensures these directories are searched and made
/// available to child processes and shells.
class PlatformEnvironment {
  static List<String>? _cachedSearchPaths;
  static Map<String, String>? _cachedEnvironment;

  /// Returns the augmented list of binary directory paths.
  static List<String> get searchPaths {
    if (kIsWeb) return const [];
    if (_cachedSearchPaths != null) return _cachedSearchPaths!;

    final paths = <String>[];
    final seen = <String>{};

    void addPath(String dir) {
      if (dir.trim().isEmpty) return;
      final normalized = dir.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
      if (seen.add(normalized)) {
        paths.add(dir);
      }
    }

    final rawPath = Platform.environment['PATH'] ?? '';
    final separator = Platform.isWindows ? ';' : ':';

    // 1. On macOS desktop, if PATH is the bare launchd minimal set, probe login shell PATH
    if (Platform.isMacOS &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
        final res = Process.runSync(
          shell,
          ['-l', '-c', 'printf "%s" "\$PATH"'],
          runInShell: false,
        );
        if (res.exitCode == 0 && res.stdout is String && (res.stdout as String).isNotEmpty) {
          final shellPaths = (res.stdout as String).split(':');
          for (final p in shellPaths) {
            addPath(p);
          }
        }
      } catch (_) {}
    }

    // 2. Add existing environment PATH entries
    if (rawPath.isNotEmpty) {
      for (final p in rawPath.split(separator)) {
        addPath(p);
      }
    }

    // 3. User home-relative binary paths
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];

    if (home != null && home.isNotEmpty) {
      final sep = Platform.pathSeparator;
      if (Platform.isWindows) {
        addPath('$home$sep.local${sep}bin');
        final appData = Platform.environment['APPDATA'];
        final localAppData = Platform.environment['LOCALAPPDATA'];
        if (appData != null) addPath('$appData${sep}npm');
        if (localAppData != null) addPath('$localAppData${sep}npm');
      } else {
        addPath('$home/.local/bin');
        addPath('$home/.local/share/pi-node/current/bin');
        addPath('$home/.cargo/bin');
        addPath('$home/.bun/bin');

        // Check ~/.nvm/versions/node/*/bin
        try {
          final nvmDir = Directory('$home/.nvm/versions/node');
          if (nvmDir.existsSync()) {
            final versions = nvmDir.listSync().whereType<Directory>().toList();
            // Sort versions descending
            versions.sort((a, b) => b.path.compareTo(a.path));
            for (final v in versions) {
              addPath('${v.path}/bin');
            }
          }
        } catch (_) {}
      }
    }

    // 4. Bundled runtime directory (e.g. PiFrame.app/Contents/MacOS where node is bundled)
    try {
      final exe = Platform.resolvedExecutable;
      if (exe.isNotEmpty) {
        final bundleDir = File(exe).parent.path;
        addPath(bundleDir);
      }
    } catch (_) {}

    // 5. Standard POSIX / Homebrew locations
    if (!Platform.isWindows) {
      addPath('/opt/homebrew/bin');
      addPath('/opt/homebrew/sbin');
      addPath('/usr/local/bin');
      addPath('/usr/local/sbin');
      addPath('/usr/bin');
      addPath('/bin');
      addPath('/usr/sbin');
      addPath('/sbin');
    }

    _cachedSearchPaths = paths;
    return paths;
  }

  /// Returns an augmented environment map suitable for passing to [Process.start] or [Process.run].
  static Map<String, String> get environment {
    if (kIsWeb) return const {};
    if (_cachedEnvironment != null) return _cachedEnvironment!;

    final env = Map<String, String>.from(Platform.environment);
    final sep = Platform.isWindows ? ';' : ':';
    env['PATH'] = searchPaths.join(sep);
    _cachedEnvironment = env;
    return env;
  }

  /// Finds the absolute path to an executable by searching [searchPaths].
  ///
  /// On Windows, automatically checks `.exe`, `.cmd`, and `.bat` extensions.
  static String? findExecutable(String name) {
    if (kIsWeb) return null;

    // Direct check if name is already an existing path
    if (name.contains(Platform.pathSeparator) || (!Platform.isWindows && name.contains('/'))) {
      final f = File(name);
      if (f.existsSync()) return f.path;
    }

    final extensions = Platform.isWindows
        ? ['', '.cmd', '.exe', '.bat']
        : [''];

    final sep = Platform.pathSeparator;
    for (final dir in searchPaths) {
      for (final ext in extensions) {
        final candidate = '$dir$sep$name$ext';
        try {
          final file = File(candidate);
          if (file.existsSync()) {
            return file.path;
          }
        } catch (_) {}
      }
    }

    return null;
  }

  /// For testing: reset cached paths and environment.
  static void resetCache() {
    _cachedSearchPaths = null;
    _cachedEnvironment = null;
  }
}
