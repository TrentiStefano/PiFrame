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

import '../app/harness_mode.dart';

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
    int maxDepth = 500,
    String? filter,
    int maxEntries = 500,
  }) =>
      serializeTreeResult(
            root,
            maxDepth: maxDepth,
            filter: filter,
            maxEntries: maxEntries,
          )['widgets']
          as List<Map<String, Object?>>;

  static Map<String, Object?> serializeTreeResult(
    Element root, {
    int maxDepth = 500,
    String? filter,
    int maxEntries = 500,
  }) {
    final entries = <Map<String, Object?>>[];
    final normalizedFilter = filter?.toLowerCase();
    var truncated = false;

    void visit(Element element, int depth) {
      if (entries.length >= maxEntries || depth > maxDepth) {
        truncated = true;
        return;
      }
      if (_isOnstage(element)) {
        final widget = element.widget;
        final key = _stringValueKey(widget.key);
        final text = _treeText(widget, element);
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
              'covered': isCovered(element),
            });
          }
        }
      }
      if (depth >= maxDepth) {
        element.visitChildElements((_) => truncated = true);
        return;
      }
      element.visitChildElements((child) => visit(child, depth + 1));
    }

    visit(root, 0);
    return {'widgets': entries, 'truncated': truncated};
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
    if (renderObject == null) return true;
    if (!renderObject.attached) return false;
    if (renderObject is RenderBox &&
        (!renderObject.hasSize || renderObject.size.isEmpty)) {
      return false;
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

  static String? _treeText(Widget widget, Element element) {
    final buttonText = _buttonLabel(widget, element);
    if (buttonText != null && buttonText.isNotEmpty) return buttonText;
    final text = _textWidgetContent(widget);
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static String? _buttonLabel(Widget widget, Element element) {
    if (widget is IconButton) return widget.tooltip;
    if (widget is! ButtonStyleButton) return null;
    final labels = <String>[];
    void visit(Element descendant) {
      final child = descendant.widget;
      if (child is Text || child is RichText) {
        final text = _textWidgetContent(child);
        if (text != null && text.isNotEmpty) labels.add(text);
        return;
      }
      if (child is Tooltip) {
        final text = _textWidgetContent(child);
        if (text != null && text.isNotEmpty) labels.add(text);
      }
      descendant.visitChildElements(visit);
    }

    element.visitChildElements(visit);
    return labels.isEmpty ? null : labels.join(' ');
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

  static Future<void> dispatchPointer(
    Offset position, {
    required HarnessPointerAction kind,
    Offset delta = Offset.zero,
  }) async {
    final pointer = _nextPointer++;
    switch (kind) {
      case HarnessPointerAction.tap:
      case HarnessPointerAction.tapAt:
        _sendTouchTap(pointer, position);
      case HarnessPointerAction.doubleTap:
        _sendTouchTap(pointer, position);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        _sendTouchTap(_nextPointer++, position);
      case HarnessPointerAction.longPress:
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
      case HarnessPointerAction.rightClick:
        GestureBinding.instance.handlePointerEvent(
          PointerDownEvent(
            pointer: pointer,
            position: position,
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryButton,
          ),
        );
        GestureBinding.instance.handlePointerEvent(
          PointerUpEvent(
            pointer: pointer,
            position: position,
            kind: PointerDeviceKind.mouse,
          ),
        );
      case HarnessPointerAction.drag:
        GestureBinding.instance.handlePointerEvent(
          PointerDownEvent(
            pointer: pointer,
            position: position,
            kind: PointerDeviceKind.mouse,
            buttons: kPrimaryButton,
          ),
        );
        var previous = position;
        for (var step = 1; step <= 5; step++) {
          final next =
              position + Offset(delta.dx * step / 5, delta.dy * step / 5);
          GestureBinding.instance.handlePointerEvent(
            PointerMoveEvent(
              pointer: pointer,
              position: next,
              delta: next - previous,
              kind: PointerDeviceKind.mouse,
              buttons: kPrimaryButton,
            ),
          );
          previous = next;
        }
        GestureBinding.instance.handlePointerEvent(
          PointerUpEvent(
            pointer: pointer,
            position: previous,
            kind: PointerDeviceKind.mouse,
          ),
        );
      case HarnessPointerAction.hover:
        GestureBinding.instance.handlePointerEvent(
          PointerHoverEvent(
            pointer: pointer,
            position: position,
            kind: PointerDeviceKind.mouse,
          ),
        );
      case HarnessPointerAction.scroll:
        GestureBinding.instance.handlePointerEvent(
          PointerScrollEvent(
            device: pointer,
            position: position,
            scrollDelta: delta,
            kind: PointerDeviceKind.mouse,
          ),
        );
    }
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

Map<String, Object?> _mediaState(Element? root) {
  final media = root == null ? null : MediaQuery.maybeOf(root);
  final overrides = harnessMediaOverrides.value;
  return {
    if (media != null) ...{
      'textScale': media.textScaler.scale(1),
      'reduceMotion': media.disableAnimations,
      'brightness': media.platformBrightness.name,
    },
    'overrides': {
      'textScale': overrides.textScale,
      'reduceMotion': overrides.reduceMotion,
      'brightness': overrides.brightness?.name,
    },
  };
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
  developer.registerExtension('ext.piframe.tapAt', (method, params) async {
    return _dispatchPointer(params, kind: _PointerAction.tapAt);
  });
  developer.registerExtension('ext.piframe.rightClick', (method, params) async {
    return _dispatchPointer(params, kind: _PointerAction.rightClick);
  });
  developer.registerExtension('ext.piframe.doubleTap', (method, params) async {
    return _dispatchPointer(params, kind: _PointerAction.doubleTap);
  });
  developer.registerExtension('ext.piframe.drag', (method, params) async {
    return _dispatchPointer(params, kind: _PointerAction.drag);
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

  developer.registerExtension('ext.piframe.media', (method, params) async {
    if (!isHarnessMode) {
      return _result({
        'ok': false,
        'error': 'Media overrides require harness mode',
      });
    }
    final textScale = params['textScale'] == null
        ? null
        : double.tryParse(params['textScale']!);
    final reduceMotion = params['reduceMotion'] == null
        ? null
        : switch (params['reduceMotion']) {
            'on' => true,
            'off' => false,
            _ => null,
          };
    final brightness = switch (params['brightness']) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      null => null,
      _ => null,
    };
    if (params['textScale'] != null &&
        (textScale == null || !textScale.isFinite || textScale <= 0)) {
      return _result({
        'ok': false,
        'error': 'textScale must be a positive number',
      });
    }
    if (params['reduceMotion'] != null && reduceMotion == null) {
      return _result({'ok': false, 'error': 'reduceMotion must be on or off'});
    }
    if (params['brightness'] != null && brightness == null) {
      return _result({
        'ok': false,
        'error': 'brightness must be light or dark',
      });
    }
    setHarnessMediaOverrides(
      textScale: textScale,
      reduceMotion: reduceMotion,
      brightness: brightness,
      reset: _isTrue(params['reset']),
    );
    return _result({
      'ok': true,
      'media': _mediaState(WidgetsBinding.instance.rootElement),
    });
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
      final maxDepth = int.tryParse(params['maxDepth'] ?? '') ?? 500;
      final maxEntries = int.tryParse(params['maxEntries'] ?? '') ?? 500;
      final tree = HarnessInspector.serializeTreeResult(
        root,
        maxDepth: maxDepth.clamp(0, 500),
        maxEntries: maxEntries.clamp(0, 5000),
        filter: params['filter'],
      );
      return _result({'ok': true, ...tree});
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
        'media': _mediaState(root),
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
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return _result({'ok': false, 'error': 'Widget tree is not ready'});
    }
    Element? element;
    Offset position;
    if (kind == _PointerAction.tapAt) {
      final x = double.tryParse(params['x'] ?? '');
      final y = double.tryParse(params['y'] ?? '');
      if (x == null || y == null || !x.isFinite || !y.isFinite) {
        return _result({
          'ok': false,
          'error': 'tapAt requires numeric x and y',
        });
      }
      position = Offset(x, y);
    } else {
      final selector = _selector(params);
      if (selector == null) {
        return _result({'ok': false, 'error': 'Pass key or text'});
      }
      element = HarnessInspector.findTarget(
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
      position = renderObject.localToGlobal(
        renderObject.size.center(Offset.zero),
      );
    }
    final covered = element != null && HarnessInspector.isCovered(element);
    var delta = Offset.zero;
    if (kind == _PointerAction.drag || kind == _PointerAction.scroll) {
      final dx = double.tryParse(params['dx'] ?? '');
      final dy = double.tryParse(params['dy'] ?? '');
      if (dx == null || dy == null || !dx.isFinite || !dy.isFinite) {
        return _result({
          'ok': false,
          'error': '${kind.name} requires numeric dx and dy',
        });
      }
      delta = Offset(dx, dy);
    }
    await HarnessInspector.dispatchPointer(
      position,
      kind: HarnessPointerAction.values.byName(kind.name),
      delta: delta,
    );
    return _result({'ok': true, 'covered': covered});
  } catch (error) {
    return _result({'ok': false, 'error': '$error'});
  }
}

void _sendTouchTap(int pointer, Offset position) {
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

enum HarnessPointerAction {
  tap,
  tapAt,
  rightClick,
  doubleTap,
  drag,
  longPress,
  hover,
  scroll,
}

enum _PointerAction {
  tap,
  tapAt,
  rightClick,
  doubleTap,
  drag,
  longPress,
  hover,
  scroll,
}

class _HarnessSelector {
  const _HarnessSelector({this.key, this.text, required this.index});

  final String? key;
  final String? text;
  final int index;
}
