import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Files and folders on the local disk.
abstract class FileSystemService {
  Future<bool> fileExists(String path);

  Future<bool> directoryExists(String path);

  Future<String> readText(String path);

  Future<void> writeText(String path, String contents);

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
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<String> readText(String path) => File(path).readAsString();

  @override
  Future<void> writeText(String path, String contents) => File(path).writeAsString(contents);

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
