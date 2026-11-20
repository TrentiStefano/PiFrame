import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/app/desktop_chrome.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/layout/layout_store.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame/ui/frame_focus.dart';

/// Plan section 13 item 3: every interactive control is reachable by Tab, shows a
/// focus ring, and has a semantic label.
///
/// The sweep pumps the real [AppShell] with a seeded session, presses Tab until focus
/// comes back to the first stop, and checks every stop. Each stop needs a label (its
/// focused semantics node, or the tooltip or semantics label above it, or the visible
/// text inside it) and a painted focus indicator (a [FrameFocusRing], a Material ink
/// response, or a text field). The whole screen also passes the labelled tap target
/// guideline.
ProviderContainer _shellContainer() => ProviderContainer(
  overrides: [
    desktopWindowLifecycleProvider.overrideWithValue(false),
    desktopChromeProvider.overrideWithValue(false),
    activeSessionIdProvider.overrideWith((ref) => 'session_1'),
    connectionStateProvider.overrideWith(
      (ref) => Stream.value(DaemonConnectionState.connected),
    ),
    sessionListProvider.overrideWith((ref) async => const []),
    sessionStateFamily('session_1').overrideWith(
      (ref) =>
          SessionStateNotifier('session_1', null)
            ..state = SessionState(sessionId: 'session_1', cwd: 'C:/repo'),
    ),
    repositoryStateProvider('session_1')
        .overrideWith((ref) => RepositoryController('session_1', () => null)),
  ],
);

/// The semantics node that the tree marks as focused, if any.
SemanticsNode? _focusedSemantics() {
  SemanticsNode? found;
  void visit(SemanticsNode node) {
    if (found != null) return;
    // hasFlag is deprecated in favour of flagsCollection, which reports the same flag
    // for this tree; flagsCollection did not match the focused node here.
    // ignore: deprecated_member_use
    if (node.hasFlag(SemanticsFlag.isFocused)) {
      found = node;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return found == null;
    });
  }

  // The binding's own pipeline owner is the one whose semantics tree the test tree
  // reports; rootPipelineOwner does not expose the focused flags here.
  // ignore: deprecated_member_use
  final root = WidgetsBinding.instance.pipelineOwner.semanticsOwner
      ?.rootSemanticsNode;
  if (root != null) visit(root);
  return found;
}

/// The label a screen reader would announce for [node], or '' when there is none.
String _labelFor(FocusNode node) {
  final semantics = _focusedSemantics();
  if (semantics != null) {
    final own = [
      semantics.label,
      semantics.hint,
      semantics.value,
      semantics.tooltip,
    ].where((s) => s.isNotEmpty).join(' | ');
    if (own.isNotEmpty) return own;
  }
  final element = node.context as Element?;
  String? above;
  element?.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Tooltip && (widget.message ?? '').isNotEmpty) {
      above = widget.message;
    } else if (widget is Semantics &&
        (widget.properties.label ?? '').isNotEmpty) {
      above = widget.properties.label;
    }
    return above == null;
  });
  if (above != null) return above!;
  // A button's visible text is its label.
  String? inside;
  void collect(Element e, int depth) {
    if (inside != null || depth > 12) return;
    final widget = e.widget;
    if (widget is Text && (widget.data ?? '').isNotEmpty) {
      inside = widget.data;
      return;
    }
    e.visitChildren((child) => collect(child, depth + 1));
  }

  element?.visitChildren((child) => collect(child, 0));
  return inside ?? '';
}

/// The focus indicator painted for [node]: a [FrameFocusRing], a Material ink
/// response (its focus highlight), or a text field. 'none' when there is none.
String _indicatorFor(FocusNode node) {
  var indicator = 'none';
  (node.context as Element?)?.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is FrameFocusRing) {
      indicator = 'ring';
      return false;
    }
    if (widget is InkResponse || widget is InkWell) {
      indicator = 'ink';
      return false;
    }
    if (widget is EditableText) {
      indicator = 'field';
      return false;
    }
    return true;
  });
  return indicator;
}

class _Stop {
  _Stop(this.index, this.name, this.label, this.indicator, this.ringPainted);
  final int index;
  final String name;
  final String label;
  final String indicator;

  /// True when a [FrameFocusRing] is painted for this stop right now (keyboard focus).
  final bool ringPainted;

  bool get ok =>
      label.trim().isNotEmpty &&
      indicator != 'none' &&
      (indicator != 'ring' || ringPainted);

  @override
  String toString() =>
      '#$index $name label="$label" indicator=$indicator ring=$ringPainted'
      '${ok ? '' : '  <-- FAIL'}';
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pi_frame_a11y_test_');
    LayoutStore.instance.setStorageFileForTesting(
      File('${tempDir.path}/layout.json'),
    );
  });

  tearDown(() {
    LayoutStore.instance.setStorageFileForTesting(null);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets(
    'Tab sweep: every focus stop has a label and a focus indicator',
    (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      final container = _shellContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AppShell()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final stops = <_Stop>[];
      FocusNode? first;
      for (var step = 0; step < 150; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 50));
        final node = FocusManager.instance.primaryFocus;
        if (node == null) continue;
        if (first == null) {
          first = node;
        } else if (identical(node, first)) {
          break;
        }
        stops.add(
          _Stop(
            stops.length + 1,
            node.debugLabel ?? node.context?.widget.runtimeType.toString() ?? '?',
            _labelFor(node),
            _indicatorFor(node),
            find.byKey(const ValueKey<String>('frame-focus-ring')).evaluate().isNotEmpty,
          ),
        );
      }

      // ignore: avoid_print
      print('TAB SWEEP ${stops.length} focus stops');
      for (final stop in stops) {
        // ignore: avoid_print
        print('TAB SWEEP $stop');
      }
      expect(stops.length, greaterThanOrEqualTo(25));
      expect(
        stops.where((s) => !s.ok).map((s) => s.toString()).toList(),
        isEmpty,
        reason: 'every Tab stop needs a label and a focus indicator',
      );

      // The whole screen: every tappable node has a label.
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
