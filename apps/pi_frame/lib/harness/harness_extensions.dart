import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class HarnessInspector {
  const HarnessInspector._();

  static List<Element> findMatches(Element root, {String? key, String? text}) {
    final matches = <Element>[];
    void visit(Element element) {
      if (_isOnstage(element) &&
          _matches(element.widget, key: key, text: text)) {
        matches.add(element);
      }
      element.visitChildElements(visit);
    }

    visit(root);
    return matches;
  }

  static Element? findTarget(
    Element root, {
    String? key,
    String? text,
    int index = 0,
  }) {
    if (index < 0) return null;
    final matches = findMatches(root, key: key, text: text);
    return index < matches.length ? matches[index] : null;
  }

  static List<Map<String, Object?>> serializeTree(
    Element root, {
    int maxDepth = 200,
    String? filter,
    int maxEntries = 500,
  }) {
    final entries = <Map<String, Object?>>[];
    final normalizedFilter = filter?.toLowerCase();

    void visit(Element element, int depth) {
      if (entries.length >= maxEntries || depth > maxDepth) return;
      if (_isOnstage(element)) {
        final widget = element.widget;
        final key = _stringValueKey(widget.key);
        final text = _treeText(widget);
        final isButton = _isButton(widget);
        if (key != null || text != null || isButton || widget is TextField) {
          final searchable = '${widget.runtimeType} ${key ?? ''} ${text ?? ''}'
              .toLowerCase();
          if (normalizedFilter == null ||
              searchable.contains(normalizedFilter)) {
            final renderObject = element.findRenderObject();
            final rect = renderObject is RenderBox
                ? _globalRect(renderObject)
                : null;
            entries.add({
              'type': widget.runtimeType.toString(),
              ...?(key == null ? null : <String, Object?>{'key': key}),
              if (text != null && text.isNotEmpty) 'text': text,
              if (rect case final rect?)
                'rect': [rect.left, rect.top, rect.width, rect.height],
            });
          }
        }
      }
      if (entries.length >= maxEntries || depth >= maxDepth) return;
      element.visitChildElements((child) => visit(child, depth + 1));
    }

    visit(root, 0);
    return entries;
  }

  static bool _isOnstage(Element element) {
    if (!element.mounted) return false;
    var offstage = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget case Offstage(offstage: true)) {
        offstage = true;
        return false;
      }
      return true;
    });
    if (offstage) return false;
    final renderObject = element.findRenderObject();
    if (renderObject == null || !renderObject.attached) return false;
    if (renderObject is RenderBox) {
      if (!renderObject.hasSize || renderObject.size.isEmpty) return false;
      final result = BoxHitTestResult();
      if (!renderObject.hitTest(
        result,
        position: renderObject.size.center(Offset.zero),
      )) {
        return false;
      }
    }
    return true;
  }

  static bool _matches(Widget widget, {String? key, String? text}) {
    final keyMatches =
        key != null &&
        widget.key != null &&
        (widget.key.toString() == key ||
            (widget.key is ValueKey &&
                (widget.key as ValueKey).value.toString() == key));
    if (keyMatches) return true;
    if (text == null) return false;
    if (widget is Text && _textWidgetContent(widget) == text) return true;
    if (widget is RichText && widget.text.toPlainText() == text) return true;
    if (widget is TextField &&
        (widget.decoration?.labelText == text ||
            widget.decoration?.hintText == text)) {
      return true;
    }
    if (widget is Tooltip && _textWidgetContent(widget) == text) return true;
    if (widget is Semantics && widget.properties.label == text) return true;
    return false;
  }

  static String? _stringValueKey(Key? key) {
    if (key is ValueKey<String>) return key.value;
    return null;
  }

  static String? _textWidgetContent(Widget widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    if (widget is RichText) return widget.text.toPlainText();
    if (widget is EditableText) return widget.controller.text;
    if (widget is TextField) {
      return widget.decoration?.labelText ?? widget.decoration?.hintText;
    }
    if (widget is Tooltip) {
      return widget.message ?? widget.richMessage?.toPlainText();
    }
    if (widget is Semantics) return widget.properties.label;
    return null;
  }

  static String? _treeText(Widget widget) {
    final text = _textWidgetContent(widget);
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static bool _isButton(Widget widget) =>
      widget is ButtonStyleButton || widget is IconButton || widget is InkWell;

  static Rect? _globalRect(RenderBox box) {
    if (!box.attached || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  static bool isCovered(Element element) {
    final renderObject = element.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return false;
    }
    final center = renderObject.localToGlobal(
      renderObject.size.center(Offset.zero),
    );
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final hitTest = HitTestResult();
    RendererBinding.instance.hitTestInView(hitTest, center, views.first.viewId);
    return !_hitPathContains(hitTest, renderObject);
  }

  static bool _hitPathContains(HitTestResult hitTest, RenderObject target) {
    for (final entry in hitTest.path) {
      if (entry.target is! RenderObject) continue;
      RenderObject? current = entry.target as RenderObject;
      while (current != null) {
        if (identical(current, target)) return true;
        current = current.parent;
      }
    }
    return false;
  }
}

Brightness? _findBrightness(Element root) {
  Brightness? brightness;
  void visit(Element element) {
    if (brightness != null) return;
    final widget = element.widget;
    if (widget is Theme) {
      brightness = widget.data.brightness;
      return;
    }
    element.visitChildElements(visit);
  }

  visit(root);
  return brightness;
}

int _nextPointer = 1;
final Stopwatch _keyClock = Stopwatch()..start();

void registerHarnessExtensions(GlobalKey rootBoundaryKey) {
  developer.registerExtension('ext.piframe.ping', (method, params) async {
    return _result({'ok': true});
  });

  developer.registerExtension('ext.piframe.screenshot', (method, params) async {
    try {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      final boundary = rootBoundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
        return _result({
          'ok': false,
          'error': 'Root render boundary is not ready',
        });
      }
      final pixelRatio = double.tryParse(params['pixelRatio'] ?? '') ?? 1.0;
      if (!pixelRatio.isFinite || pixelRatio <= 0) {
        return _result({
          'ok': false,
          'error': 'pixelRatio must be a positive number',
        });
      }
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          return _result({'ok': false, 'error': 'PNG encoding failed'});
        }
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final path = params['path'];
        if (path != null && path.isNotEmpty) {
          await File(path).writeAsBytes(bytes, flush: true);
          return _result({
            'ok': true,
            'path': path,
            'width': image.width,
            'height': image.height,
          });
        }
        return _result({
          'ok': true,
          'width': image.width,
          'height': image.height,
          'pngBase64': base64Encode(bytes),
        });
      } finally {
        image.dispose();
      }
    } catch (error) {
      return _result({'ok': false, 'error': '$error'});
    }
  });

  developer.registerExtension('ext.piframe.tap', (method, params) async {
    return _dispatchPointer(params, kind: _PointerAction.tap);
  });
  developer.registerExtension('ext.piframe.longPress', (method, params) async {
    return _dispatchPointer(params, kind: _PointerAction.longPress);
  });
  developer.registerExtension('ext.piframe.hover', (method, params) async {
    return _dispatchPointer(params, kind: _PointerAction.hover);
  });
  developer.registerExtension('ext.piframe.scroll', (method, params) async {
    return _dispatchPointer(params, kind: _PointerAction.scroll);
  });

  developer.registerExtension('ext.piframe.enterText', (method, params) async {
    try {
      final value = params['value'];
      if (value == null) return _result({'ok': false, 'error': 'Pass value'});
      final selector = _selector(params);
      final root = WidgetsBinding.instance.rootElement;
      if (root == null) {
        return _result({'ok': false, 'error': 'Widget tree is not ready'});
      }
      final element = selector == null
          ? null
          : HarnessInspector.findTarget(
              root,
              key: selector.key,
              text: selector.text,
              index: selector.index,
            );
      final editableState =
          _editableState(element) ??
          (selector == null ? _focusedEditableState(root) : null);
      if (editableState == null) {
        return _result({
          'ok': false,
          'error': selector == null
              ? 'No focused editable text field'
              : 'Editable target not found',
        });
      }
      editableState.userUpdateTextEditingValue(
        TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        ),
        SelectionChangedCause.keyboard,
      );
      return _result({'ok': true, 'value': value});
    } catch (error) {
      return _result({'ok': false, 'error': '$error'});
    }
  });

  developer.registerExtension('ext.piframe.sendKey', (method, params) async {
    try {
      final keyName = params['key'];
      if (keyName == null) {
        return _result({'ok': false, 'error': 'Pass key'});
      }
      final key = _keyFor(keyName);
      if (key == null) {
        return _result({'ok': false, 'error': 'Unsupported key: $keyName'});
      }
      final modifiers = <(PhysicalKeyboardKey, LogicalKeyboardKey)>[];
      if (_isTrue(params['ctrl'])) {
        modifiers.add((
          PhysicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.controlLeft,
        ));
      }
      if (_isTrue(params['shift'])) {
        modifiers.add((
          PhysicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.shiftLeft,
        ));
      }
      if (_isTrue(params['alt'])) {
        modifiers.add((
          PhysicalKeyboardKey.altLeft,
          LogicalKeyboardKey.altLeft,
        ));
      }
      if (_isTrue(params['meta'])) {
        modifiers.add((
          PhysicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.metaLeft,
        ));
      }
      final pressedModifiers = <(PhysicalKeyboardKey, LogicalKeyboardKey)>[];
      try {
        for (final modifier in modifiers) {
          _sendKeyData(modifier.$1, modifier.$2, ui.KeyEventType.down);
          pressedModifiers.add(modifier);
        }
        _sendKeyData(key.$1, key.$2, ui.KeyEventType.down, character: key.$3);
        _sendKeyData(key.$1, key.$2, ui.KeyEventType.up);
      } finally {
        for (final modifier in pressedModifiers.reversed) {
          _sendKeyData(modifier.$1, modifier.$2, ui.KeyEventType.up);
        }
      }
      return _result({'ok': true, 'key': keyName});
    } catch (error) {
      return _result({'ok': false, 'error': '$error'});
    }
  });

  developer.registerExtension('ext.piframe.resize', (method, params) async {
    try {
      final width = double.tryParse(params['width'] ?? '');
      final height = double.tryParse(params['height'] ?? '');
      if (width == null ||
          height == null ||
          !width.isFinite ||
          !height.isFinite ||
          width <= 0 ||
          height <= 0) {
        return _result({
          'ok': false,
          'error': 'width and height must be positive numbers',
        });
      }
      await windowManager.setSize(Size(width, height));
      await windowManager.setPosition(const Offset(-32000, -32000));
      return _result({'ok': true, 'width': width, 'height': height});
    } catch (error) {
      return _result({'ok': false, 'error': '$error'});
    }
  });

  developer.registerExtension('ext.piframe.tree', (method, params) async {
    try {
      final root = WidgetsBinding.instance.rootElement;
      if (root == null) {
        return _result({'ok': false, 'error': 'Widget tree is not ready'});
      }
      final maxDepth = int.tryParse(params['maxDepth'] ?? '') ?? 200;
      final entries = HarnessInspector.serializeTree(
        root,
        maxDepth: maxDepth.clamp(0, 500),
        filter: params['filter'],
      );
      return _result({'ok': true, 'widgets': entries});
    } catch (error) {
      return _result({'ok': false, 'error': '$error'});
    }
  });

  developer.registerExtension('ext.piframe.state', (method, params) async {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      final view = views.isEmpty ? null : views.first;
      final root = WidgetsBinding.instance.rootElement;
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      final focusedWidget = focusedContext?.widget;
      final brightness = root == null ? null : _findBrightness(root);
      return _result({
        'ok': true,
        if (view != null) ...{
          'size': {
            'width': view.physicalSize.width / view.devicePixelRatio,
            'height': view.physicalSize.height / view.devicePixelRatio,
          },
          'devicePixelRatio': view.devicePixelRatio,
        },
        if (brightness != null) 'brightness': brightness.name,
        'focusedWidget': focusedWidget == null
            ? null
            : {
                'type': focusedWidget.runtimeType.toString(),
                if (focusedWidget.key != null)
                  'key': focusedWidget.key.toString(),
              },
      });
    } catch (error) {
      return _result({'ok': false, 'error': '$error'});
    }
  });
}

Future<developer.ServiceExtensionResponse> _dispatchPointer(
  Map<String, String> params, {
  required _PointerAction kind,
}) async {
  try {
    final selector = _selector(params);
    if (selector == null) {
      return _result({'ok': false, 'error': 'Pass key or text'});
    }
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return _result({'ok': false, 'error': 'Widget tree is not ready'});
    }
    final element = HarnessInspector.findTarget(
      root,
      key: selector.key,
      text: selector.text,
      index: selector.index,
    );
    if (element == null) {
      return _result({'ok': false, 'error': 'Target not found'});
    }
    final renderObject = element.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return _result({'ok': false, 'error': 'Target has no visible bounds'});
    }
    final position = renderObject.localToGlobal(
      renderObject.size.center(Offset.zero),
    );
    final pointer = _nextPointer++;
    final covered = HarnessInspector.isCovered(element);
    switch (kind) {
      case _PointerAction.tap:
        GestureBinding.instance.handlePointerEvent(
          PointerDownEvent(
            pointer: pointer,
            position: position,
            kind: PointerDeviceKind.touch,
            buttons: kPrimaryButton,
          ),
        );
        GestureBinding.instance.handlePointerEvent(
          PointerUpEvent(
            pointer: pointer,
            position: position,
            kind: PointerDeviceKind.touch,
          ),
        );
      case _PointerAction.longPress:
        GestureBinding.instance.handlePointerEvent(
          PointerDownEvent(
            pointer: pointer,
            position: position,
            kind: PointerDeviceKind.touch,
            buttons: kPrimaryButton,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        GestureBinding.instance.handlePointerEvent(
          PointerUpEvent(
            pointer: pointer,
            position: position,
            kind: PointerDeviceKind.touch,
          ),
        );
      case _PointerAction.hover:
        GestureBinding.instance.handlePointerEvent(
          PointerHoverEvent(
            pointer: pointer,
            position: position,
            kind: PointerDeviceKind.mouse,
          ),
        );
      case _PointerAction.scroll:
        final dx = double.tryParse(params['dx'] ?? '');
        final dy = double.tryParse(params['dy'] ?? '');
        if (dx == null || dy == null || !dx.isFinite || !dy.isFinite) {
          return _result({
            'ok': false,
            'error': 'scroll requires numeric dx and dy',
          });
        }
        GestureBinding.instance.handlePointerEvent(
          PointerScrollEvent(
            device: pointer,
            position: position,
            scrollDelta: Offset(dx, dy),
            kind: PointerDeviceKind.mouse,
          ),
        );
    }
    return _result({'ok': true, 'covered': covered});
  } catch (error) {
    return _result({'ok': false, 'error': '$error'});
  }
}

EditableTextState? _focusedEditableState(Element root) {
  final focusedNode = FocusManager.instance.primaryFocus;
  if (focusedNode == null) return null;
  EditableTextState? result;
  void visit(Element candidate) {
    if (result != null) return;
    if (candidate is StatefulElement && candidate.state is EditableTextState) {
      final state = candidate.state as EditableTextState;
      if (identical(state.widget.focusNode, focusedNode)) result = state;
    }
    candidate.visitChildElements(visit);
  }

  visit(root);
  return result;
}

EditableTextState? _editableState(Element? element) {
  if (element == null) return null;
  EditableTextState? result;
  void visit(Element candidate) {
    if (result != null) return;
    if (candidate is StatefulElement && candidate.state is EditableTextState) {
      result = candidate.state as EditableTextState;
      return;
    }
    candidate.visitChildElements(visit);
  }

  visit(element);
  return result;
}

_HarnessSelector? _selector(Map<String, String> params) {
  final key = params['key'];
  final text = params['text'];
  if ((key == null || key.isEmpty) && (text == null || text.isEmpty)) {
    return null;
  }
  return _HarnessSelector(
    key: key?.isNotEmpty == true ? key : null,
    text: text?.isNotEmpty == true ? text : null,
    index: int.tryParse(params['index'] ?? '') ?? 0,
  );
}

bool _isTrue(String? value) => value == 'true' || value == '1';

void _sendKeyData(
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey logical,
  ui.KeyEventType type, {
  String? character,
}) {
  // The key data manager is the same framework path used by native platform events.
  // ignore: deprecated_member_use
  ServicesBinding.instance.keyEventManager.handleKeyData(
    ui.KeyData(
      timeStamp: _keyClock.elapsed,
      type: type,
      physical: physical.usbHidUsage,
      logical: logical.keyId,
      character: character,
      synthesized: true,
    ),
  );
}

(PhysicalKeyboardKey, LogicalKeyboardKey, String?)? _keyFor(String name) {
  final normalized = name.replaceAll('-', '').replaceAll('_', '').toLowerCase();
  final keys = <String, (PhysicalKeyboardKey, LogicalKeyboardKey, String?)>{
    'enter': (PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter, null),
    'return': (PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter, null),
    'escape': (PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape, null),
    'esc': (PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape, null),
    'tab': (PhysicalKeyboardKey.tab, LogicalKeyboardKey.tab, null),
    'space': (PhysicalKeyboardKey.space, LogicalKeyboardKey.space, ' '),
    'backspace': (
      PhysicalKeyboardKey.backspace,
      LogicalKeyboardKey.backspace,
      null,
    ),
    'delete': (PhysicalKeyboardKey.delete, LogicalKeyboardKey.delete, null),
    'arrowup': (PhysicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowUp, null),
    'arrowdown': (
      PhysicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
      null,
    ),
    'arrowleft': (
      PhysicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowLeft,
      null,
    ),
    'arrowright': (
      PhysicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      null,
    ),
    'home': (PhysicalKeyboardKey.home, LogicalKeyboardKey.home, null),
    'end': (PhysicalKeyboardKey.end, LogicalKeyboardKey.end, null),
    'pageup': (PhysicalKeyboardKey.pageUp, LogicalKeyboardKey.pageUp, null),
    'pagedown': (
      PhysicalKeyboardKey.pageDown,
      LogicalKeyboardKey.pageDown,
      null,
    ),
  };
  return keys[normalized];
}

developer.ServiceExtensionResponse _result(Map<String, Object?> value) =>
    developer.ServiceExtensionResponse.result(jsonEncode(value));

enum _PointerAction { tap, longPress, hover, scroll }

class _HarnessSelector {
  const _HarnessSelector({this.key, this.text, required this.index});

  final String? key;
  final String? text;
  final int index;
}
