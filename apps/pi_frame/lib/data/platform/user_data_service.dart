import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Small files the app keeps for the user in their home folder (`~/.piframe/`), such as pinned sessions.
/// Reads and writes are synchronous because the stores load their state in their constructors.
abstract class UserDataService {
  /// The contents of the file [name], or null when there is none or it cannot be read.
  String? read(String name);

  /// Replaces the contents of the file [name]. Throws when the file cannot be written.
  void write(String name, String contents);
}

class IoUserDataService implements UserDataService {
  const IoUserDataService();

  /// The folder the files live in, created on first use. Null on the web build.
  Directory? _folder() {
    if (kIsWeb) return null;
    final env = Platform.environment;
    final home = Platform.isWindows ? (env['USERPROFILE'] ?? 'C:\\Users\\Default') : (env['HOME'] ?? '/tmp');
    final dir = Directory('$home/.piframe');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  @override
  String? read(String name) {
    try {
      final dir = _folder();
      if (dir == null) return null;
      final file = File('${dir.path}/$name');
      return file.existsSync() ? file.readAsStringSync() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String name, String contents) {
    final dir = _folder();
    if (dir == null) return;
    File('${dir.path}/$name').writeAsStringSync(contents);
  }
}

final userDataServiceProvider = Provider<UserDataService>((ref) => const IoUserDataService());
