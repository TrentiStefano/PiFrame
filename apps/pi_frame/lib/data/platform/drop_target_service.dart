import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_dialog_service.dart';

/// Drag and drop of files from the desktop onto the app.
abstract class DropTargetService {
  /// Wraps [child] so that files dropped on it are reported. [onDragEntered] and
  /// [onDragExited] fire while a drag hovers over the target.
  Widget dropTarget({
    required Widget child,
    required void Function(List<PickedFile> files) onDrop,
    void Function()? onDragEntered,
    void Function()? onDragExited,
  });
}

class DesktopDropService implements DropTargetService {
  const DesktopDropService();

  @override
  Widget dropTarget({
    required Widget child,
    required void Function(List<PickedFile> files) onDrop,
    void Function()? onDragEntered,
    void Function()? onDragExited,
  }) {
    return DropTarget(
      onDragEntered: onDragEntered == null ? null : (_) => onDragEntered(),
      onDragExited: onDragExited == null ? null : (_) => onDragExited(),
      onDragDone: (details) => onDrop([for (final file in details.files) PickedFile.fromXFile(file)]),
      child: child,
    );
  }
}

final dropTargetServiceProvider = Provider<DropTargetService>((ref) => const DesktopDropService());
