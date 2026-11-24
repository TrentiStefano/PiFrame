import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native open dialogs. Results are absolute paths; an empty list or null
/// means the user cancelled.
abstract class FileDialogService {
  /// [multiple] false lets the user pick one file; the result then holds at most one path.
  Future<List<String>> pickFiles({String? label, List<String> extensions = const [], bool multiple = true});

  Future<String?> pickDirectory({String? confirmText});
}

class FileSelectorDialogService implements FileDialogService {
  const FileSelectorDialogService();

  @override
  Future<List<String>> pickFiles({String? label, List<String> extensions = const [], bool multiple = true}) async {
    final groups = extensions.isEmpty
        ? const <XTypeGroup>[]
        : [XTypeGroup(label: label ?? 'Files', extensions: extensions)];
    if (!multiple) {
      final file = await openFile(acceptedTypeGroups: groups);
      return file == null ? const [] : [file.path];
    }
    final files = await openFiles(acceptedTypeGroups: groups);
    return [for (final file in files) file.path];
  }

  @override
  Future<String?> pickDirectory({String? confirmText}) => getDirectoryPath(confirmButtonText: confirmText);
}

final fileDialogServiceProvider = Provider<FileDialogService>((ref) => const FileSelectorDialogService());
