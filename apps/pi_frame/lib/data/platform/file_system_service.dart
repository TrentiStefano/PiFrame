import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Files and folders on the local disk.
abstract class FileSystemService {
  Future<bool> fileExists(String path);

  Future<bool> directoryExists(String path);

  Future<String> readText(String path);

  Future<void> writeText(String path, String contents);

  /// Synchronous variants for the few places that must answer during build or initState.
  bool fileExistsSync(String path);

  bool directoryExistsSync(String path);

  /// The file's text, or null when the file is missing or cannot be read.
  String? readTextSync(String path);

  /// Writes [contents], creating missing parent folders. Throws when the file cannot be written.
  void writeTextSync(String path, String contents);

  /// Names of the folders directly inside [path] (empty when it is missing).
  List<String> subdirectoryNamesSync(String path);

  /// The directory the app was started in.
  String get currentDirectory;

  /// Shows the image file at [path]. [errorBuilder] runs when it cannot be shown.
  Widget imageFile(
    String path, {
    double? width,
    double? height,
    BoxFit? fit,
    required Widget Function(BuildContext, Object, StackTrace?) errorBuilder,
  });
}

class IoFileSystemService implements FileSystemService {
  const IoFileSystemService();

  @override
  String get currentDirectory => Directory.current.path;

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<String> readText(String path) => File(path).readAsString();

  @override
  Future<void> writeText(String path, String contents) => File(path).writeAsString(contents);

  @override
  bool fileExistsSync(String path) => File(path).existsSync();

  @override
  bool directoryExistsSync(String path) => Directory(path).existsSync();

  @override
  String? readTextSync(String path) {
    try {
      return File(path).readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  @override
  void writeTextSync(String path, String contents) {
    final file = File(path);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsStringSync(contents);
  }

  @override
  List<String> subdirectoryNamesSync(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    return [
      for (final entity in dir.listSync())
        if (entity is Directory) entity.path.replaceAll('\\', '/').split('/').last,
    ];
  }

  @override
  Widget imageFile(
    String path, {
    double? width,
    double? height,
    BoxFit? fit,
    required Widget Function(BuildContext, Object, StackTrace?) errorBuilder,
  }) {
    return Image.file(File(path), width: width, height: height, fit: fit, errorBuilder: errorBuilder);
  }
}

final fileSystemServiceProvider = Provider<FileSystemService>((ref) => const IoFileSystemService());
