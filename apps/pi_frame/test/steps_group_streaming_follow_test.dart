// While a running step group streams a long thinking block inside the compact
// (height-capped) list, the list must stay pinned to the latest line on every
// frame. Following the stream with a post-frame jump left one or more frames
// at a stale offset, so the earlier steps visibly jittered up and down as each
// new line arrived.
//
// The thinking text is a SelectableText, which owns a nested Scrollable. Its
// metrics notifications must not be read as the compact list's own: doing so
// toggled the overflow state (and the "show all" button) on every streamed
// line, so the whole transcript jumped up and down.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/transcript/step_grouping_settings.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
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

  testWidgets('transcript does not jump while a long thinking block streams', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const sid = 'transcript_stream';
    final entries = <SessionEntry>[
      for (int t = 0; t < 4; t++) ...[
        SessionEntry(
          id: 'u$t',
          role: 'user',
          text: 'old question $t',
          timestamp: 1000 + t * 100,
        ),
        SessionEntry(
          id: 'a$t',
          role: 'assistant',
          text: List.filled(12, 'Old answer line $t.').join('\n'),
          timestamp: 1050 + t * 100,
        ),
      ],
      SessionEntry(id: 'ucur', role: 'user', text: 'Do it', timestamp: 5000),
      SessionEntry(
        id: 'acur',
        role: 'assistant',
        text: '',
        thinking: 'First thought',
        toolCalls: [
          for (int i = 0; i < 4; i++)
            ToolExecutionState(
              toolCallId: 'tc$i',
              toolName: 'read',
              args: {'path': 'lib/f$i.dart'},
              output: 'ok',
              isRunning: false,
              startedAt: 5100,
              durationMs: 10,
            ),
        ],
        timestamp: 5100,
      ),
    ];
    final notifier = SessionStateNotifier(sid, null)
      ..state = SessionState(
        sessionId: sid,
        cwd: '/repo',
        entries: entries,
        agentStatus: AgentStatus.working,
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily(sid).overrideWith((ref) => notifier),
          stepGroupingSettingsProvider.overrideWith(
            (ref) =>
                StepGroupingSettingsNotifier()
                  ..setMode(StepGroupingMode.always),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: TranscriptView(sessionId: sid)),
        ),
      ),
    );
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final words = 'the model keeps reasoning about many alternatives'.split(
      ' ',
    );
    final groupHeader = find.byKey(
      const ValueKey('step_group_header_steps_ucur'),
    );
    final toolRow = find.byKey(const ValueKey('tool_step_header_tc3'));
    var text = '';
    double? lastTool;
    double? lastHeader;
    for (int i = 0; i < 300; i++) {
      // Token-sized chunks, with a hard line break now and then.
      text += '${words[i % words.length]}${i % 23 == 22 ? '\n' : ' '}';
      notifier.state = notifier.state.copyWith(
        streamingThinkingBlocks: {0: text},
      );
      await tester.pump(const Duration(milliseconds: 16));

      // The group header only moves up while the group grows to its cap.
      final header = tester.getTopLeft(groupHeader).dy;
      if (lastHeader != null) {
        expect(header, lessThanOrEqualTo(lastHeader + 0.5), reason: 'frame $i');
      }
      lastHeader = header;

      // Earlier steps only ever move up to make room for new lines.
      if (toolRow.evaluate().isNotEmpty) {
        final tool = tester.getTopLeft(toolRow).dy;
        if (lastTool != null) {
          expect(tool, lessThanOrEqualTo(lastTool + 0.5), reason: 'frame $i');
        }
        lastTool = tool;
      }
    }
    expect(
      find.byKey(const ValueKey('step_group_expand_all_steps_ucur')),
      findsOneWidget,
    );
  });
}
