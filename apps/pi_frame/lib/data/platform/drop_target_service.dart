import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Drag and drop of files from the desktop onto the app.
abstract class DropTargetService {
  /// Wraps [child] so that files dropped on it are reported as absolute paths.
  Widget dropTarget({required Widget child, required void Function(List<String> paths) onDrop});
}

class DesktopDropService implements DropTargetService {
  const DesktopDropService();

  @override
  Widget dropTarget({required Widget child, required void Function(List<String> paths) onDrop}) {
    return DropTarget(onDragDone: (details) => onDrop([for (final file in details.files) file.path]), child: child);
  }
}

final dropTargetServiceProvider = Provider<DropTargetService>((ref) => const DesktopDropService());
