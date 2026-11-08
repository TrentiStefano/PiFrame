// While a running step group streams a long thinking block inside the compact
// (height-capped) list, the list must stay pinned to the latest line on every
// frame. Following the stream with a post-frame jump left one or more frames
// at a stale offset, so the earlier steps visibly jittered up and down as each
// new line arrived.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/transcript_grouping.dart';
import 'package:pi_frame/features/transcript/steps_group.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

const _sid = 's_stream_follow';

StepsGroupBlock _block(String thinking, {bool streaming = true}) {
  return StepsGroupBlock(
    groupId: 'steps_u1',
    turnId: 'u1',
    steps: [
      for (int i = 0; i < 6; i++)
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
      ThinkingStep(id: 'think_1', text: thinking, isStreaming: streaming),
    ],
    isRunning: true,
    hasError: false,
    aborted: false,
    stepCount: 7,
  );
}

Widget _app(StepsGroupBlock block) => ProviderScope(
  child: MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
    home: Scaffold(
      body: SingleChildScrollView(
        child: StepsGroup(
          sessionId: _sid,
          block: block,
          tokens: FrameTokens.dark,
        ),
      ),
    ),
  ),
);

ScrollPosition _compactPosition(WidgetTester tester) {
  final scrollable = find
      .descendant(
        of: find.byKey(const ValueKey('step_group_compact_list_steps_u1')),
        matching: find.byType(Scrollable),
      )
      .first;
  return tester.state<ScrollableState>(scrollable).position;
}

void main() {
  testWidgets('streaming thinking stays pinned to the bottom on every frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final buffer = StringBuffer('Planning the change');
    await tester.pumpWidget(_app(_block(buffer.toString())));
    await tester.pump();

    final offsets = <double>[];
    for (int i = 0; i < 60; i++) {
      buffer.write('\nline $i of a long reasoning stream that keeps growing');
      await tester.pumpWidget(_app(_block(buffer.toString())));
      final position = _compactPosition(tester);
      // Pinned in the same frame the new line was laid out.
      expect(
        position.maxScrollExtent - position.pixels,
        lessThan(0.5),
        reason: 'frame $i: list lagged behind the streamed text',
      );
      offsets.add(position.pixels);
    }

    // The list overflowed and only ever moved forward (no up/down jitter).
    expect(offsets.last, greaterThan(0));
    for (int i = 1; i < offsets.length; i++) {
      expect(offsets[i], greaterThanOrEqualTo(offsets[i - 1] - 0.5));
    }
  });

  testWidgets('user scrolling up stops following the stream', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final buffer = StringBuffer('Planning the change');
    for (int i = 0; i < 40; i++) {
      buffer.write('\nline $i of a long reasoning stream');
    }
    await tester.pumpWidget(_app(_block(buffer.toString())));
    await tester.pump();
    await tester.pump();

    final list = find.byKey(const ValueKey('step_group_compact_list_steps_u1'));
    await tester.drag(list, const Offset(0, 200));
    await tester.pump();
    final pinnedAway = _compactPosition(tester).pixels;
    expect(
      _compactPosition(tester).maxScrollExtent - pinnedAway,
      greaterThan(50),
    );

    for (int i = 0; i < 5; i++) {
      buffer.write('\nmore $i');
      await tester.pumpWidget(_app(_block(buffer.toString())));
      await tester.pump();
    }
    expect(_compactPosition(tester).pixels, closeTo(pinnedAway, 0.5));
  });
}
