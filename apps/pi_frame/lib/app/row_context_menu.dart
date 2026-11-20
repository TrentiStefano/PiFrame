import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// True for the keys that open a context menu from the keyboard: the Menu key
/// and Shift+F10, the Windows convention for a right-click.
bool isContextMenuKey(KeyEvent event) {
  if (event is! KeyDownEvent) return false;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.contextMenu) return true;
  return key == LogicalKeyboardKey.f10 &&
      HardwareKeyboard.instance.isShiftPressed;
}

/// Global rect of a row's render box: the anchor of a menu opened from the
/// keyboard, so the menu sits on the row it belongs to.
Rect rowAnchorRect(BuildContext rowContext) {
  final box = rowContext.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Anchor for a menu opened by a pointer at [position].
Rect pointerAnchorRect(Offset position) =>
    Rect.fromLTWH(position.dx, position.dy, 1, 1);

/// Menu position for [anchor] inside the window that holds [context].
RelativeRect menuPositionFor(BuildContext context, Rect anchor) =>
    RelativeRect.fromRect(anchor, Offset.zero & MediaQuery.sizeOf(context));

/// One context-menu opener per row key of a list. A pane registers an opener
/// while it builds each row; its key handler calls [openFor] with the cursor
/// row's key, so Shift+F10 or the Menu key opens that row's menu.
class RowMenuRegistry {
  final Map<String, VoidCallback> _openers = {};

  void register(String rowKey, VoidCallback open) => _openers[rowKey] = open;

  /// Opens the menu of [rowKey]. False when no row with that key is built.
  bool openFor(String rowKey) {
    final open = _openers[rowKey];
    if (open == null) return false;
    open();
    return true;
  }
}
