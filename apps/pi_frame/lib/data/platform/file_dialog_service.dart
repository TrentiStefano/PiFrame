import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file the user picked or dropped. [path] is absolute on desktop; [readBytes]
/// is what the browser build uploads, since its [path] only exists in the tab.
class PickedFile {
  final String path;
  final String name;
  final String? mimeType;
  final Future<Uint8List> Function() readBytes;

  const PickedFile({required this.path, required this.name, this.mimeType, required this.readBytes});

  factory PickedFile.fromXFile(XFile file) =>
      PickedFile(path: file.path, name: file.name, mimeType: file.mimeType, readBytes: file.readAsBytes);
}

/// Native open dialogs. Results are absolute paths; an empty list or null
/// means the user cancelled.
abstract class FileDialogService {
  /// [multiple] false lets the user pick one file; the result then holds at most one file.
  Future<List<PickedFile>> pickFiles({String? label, List<String> extensions = const [], bool multiple = true});

  Future<String?> pickDirectory({String? confirmText});
}

class FileSelectorDialogService implements FileDialogService {
  const FileSelectorDialogService();

  @override
  Future<List<PickedFile>> pickFiles({String? label, List<String> extensions = const [], bool multiple = true}) async {
    final groups = extensions.isEmpty
        ? const <XTypeGroup>[]
        : [XTypeGroup(label: label ?? 'Files', extensions: extensions)];
    if (!multiple) {
      final file = await openFile(acceptedTypeGroups: groups);
      return file == null ? const [] : [PickedFile.fromXFile(file)];
    }
    final files = await openFiles(acceptedTypeGroups: groups);
    return [for (final file in files) PickedFile.fromXFile(file)];
  }

  @override
  Future<String?> pickDirectory({String? confirmText}) => getDirectoryPath(confirmButtonText: confirmText);
}

final fileDialogServiceProvider = Provider<FileDialogService>((ref) => const FileSelectorDialogService());
