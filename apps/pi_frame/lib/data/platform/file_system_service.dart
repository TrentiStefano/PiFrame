import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Files and folders on the local disk.
abstract class FileSystemService {
  Future<bool> fileExists(String path);

  Future<bool> directoryExists(String path);

  Future<String> readText(String path);

  Future<void> writeText(String path, String contents);

  /// The directory the app was started in.
  String get currentDirectory;
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
}

final fileSystemServiceProvider = Provider<FileSystemService>((ref) => const IoFileSystemService());
