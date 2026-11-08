// Expanded step groups show a compact list limited to half the window height,
// scrollable, with a button that expands it to full height. Collapsing and
// re-expanding returns to the compact list.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/transcript_grouping.dart';
import 'package:pi_frame/features/transcript/step_group_expansion.dart';
import 'package:pi_frame/features/transcript/steps_group.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

const _sid = 's_compact';
const _windowHeight = 600.0;

StepsGroupBlock _block({required int steps, bool isRunning = false}) {
  final items = <StepItem>[
    for (int i = 0; i < steps; i++)
      ToolStep(
        id: 'tool_$i',
        tool: ToolExecutionState(
          toolCallId: 'tool_$i',
          toolName: 'read',
          args: {'path': 'lib/file_$i.dart'},
          output: 'ok',
          isRunning: false,
          durationMs: 10,
        ),
      ),
  ];
  return StepsGroupBlock(
    groupId: 'steps_u1',
    turnId: 'u1',
    steps: items,
    isRunning: isRunning,
    hasError: false,
    aborted: false,
    stepCount: steps,
    elapsed: const Duration(seconds: 12),
  );
}

Widget _app(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

Finder _compactList() => find.byKey(const ValueKey('step_group_compact_list_steps_u1'));
Finder _expandAll() => find.byKey(const ValueKey('step_group_expand_all_steps_u1'));
Finder _header() => find.byKey(const ValueKey('step_group_header_steps_u1'));

Future<void> _setWindow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, _windowHeight);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('many steps: compact list capped at half the window, then expand all', (
    tester,
  ) async {
    await _setWindow(tester);
    await tester.pumpWidget(
      _app(StepsGroup(sessionId: _sid, block: _block(steps: 60), tokens: FrameTokens.dark)),
    );
    // Settled group starts collapsed: expand it.
    await tester.tap(_header());
    await tester.pumpAndSettle();

    expect(_compactList(), findsOneWidget);
    expect(tester.getSize(_compactList()).height, lessThanOrEqualTo(_windowHeight / 2 + 0.5));
    expect(_expandAll(), findsOneWidget);
    expect(find.text('Mostra tutti i passaggi (60)'), findsOneWidget);

    // The compact list scrolls on its own.
    final scrollable = find.descendant(of: _compactList(), matching: find.byType(Scrollable));
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.tap(_expandAll());
    await tester.pumpAndSettle();
    expect(_compactList(), findsNothing);
    expect(_expandAll(), findsNothing);
    final group = tester.getSize(find.byType(StepsGroup)).height;
    expect(group, greaterThan(_windowHeight));

    // Collapse and expand again: back to the compact list.
    await tester.tap(_header());
    await tester.pumpAndSettle();
    expect(_compactList(), findsNothing);
    await tester.tap(_header());
    await tester.pumpAndSettle();
    expect(_compactList(), findsOneWidget);
    expect(_expandAll(), findsOneWidget);
  });

  testWidgets('few steps: no limit button', (tester) async {
    await _setWindow(tester);
    await tester.pumpWidget(
      _app(StepsGroup(sessionId: _sid, block: _block(steps: 3), tokens: FrameTokens.dark)),
    );
    await tester.tap(_header());
    await tester.pumpAndSettle();
    expect(_compactList(), findsOneWidget);
    expect(_expandAll(), findsNothing);
    expect(find.text('lib/file_2.dart'), findsOneWidget);
  });

  testWidgets('auto-collapse at turn end resets the full-height list', (tester) async {
    await _setWindow(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Widget build(bool running) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StepsGroup(
              sessionId: _sid,
              block: _block(steps: 60, isRunning: running),
              tokens: FrameTokens.dark,
            ),
          ),
        ),
      ),
    );

    // Running: open by default; expand to full height.
    await tester.pumpWidget(build(true));
    // Overflow is detected after layout and shown on the following frames.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_expandAll(), findsOneWidget);
    await tester.tap(_expandAll());
    await tester.pump();
    expect(
      container.read(stepGroupExpansionProvider(_sid)).isGroupFullyExpanded('u1'),
      isTrue,
    );

    // Turn ends: auto-collapse closes the group and drops the full height.
    await tester.pumpWidget(build(false));
    await tester.pump();
    await tester.pump();
    expect(
      container.read(stepGroupExpansionProvider(_sid)).isGroupFullyExpanded('u1'),
      isFalse,
    );

    // Re-opening shows the compact list again.
    await tester.tap(_header());
    await tester.pumpAndSettle();
    expect(_compactList(), findsOneWidget);
    expect(_expandAll(), findsOneWidget);
  });
}
