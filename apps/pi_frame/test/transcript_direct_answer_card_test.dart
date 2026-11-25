// An agent that answers straight away, with no tool calls or thinking, still
// gives a final answer: it gets the same bordered card and primary text
// colour as an answer that comes after steps, not the dimmed plain layout.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/transcript/step_grouping_settings.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/transcript_grouping.dart';
import 'package:pi_frame/features/transcript/assistant_turn_frame.dart';
import 'package:pi_frame/features/transcript/rich_content.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  testWidgets('a direct answer with no steps renders as the final answer card', (tester) async {
    const sid = 'direct_answer';
    final notifier = SessionStateNotifier(sid, null)
      ..state = const SessionState(
        sessionId: sid,
        cwd: '/repo',
        agentStatus: AgentStatus.settled,
        entries: [
          SessionEntry(id: 'u1', role: 'user', text: 'Why is it still blocked?', timestamp: 1000),
          SessionEntry(id: 'a1', role: 'assistant', text: 'One acceptance test is failing.', timestamp: 2000),
        ],
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily(sid).overrideWith((ref) => notifier),
          stepGroupingSettingsProvider.overrideWith(
            (ref) => StepGroupingSettingsNotifier()..setMode(StepGroupingMode.full),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: TranscriptView(sessionId: sid)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final answer = find.ancestor(
      of: find.text('One acceptance test is failing.', findRichText: true),
      matching: find.byType(AssistantTurnFrame),
    );
    expect(answer, findsOneWidget);
    expect(
      tester.widget<AssistantTurnFrame>(answer).isCard,
      isTrue,
      reason: 'the answer is shown in the bordered final-answer card',
    );
    final content = tester.widget<RichContent>(find.descendant(of: answer, matching: find.byType(RichContent)));
    expect(content.textColor, isNull, reason: 'primary text colour, not the dimmed secondary one');
    await tester.pumpWidget(const SizedBox());
  });

  // While the agent works between tool calls, or streams, its latest message
  // is not the final answer yet: showing it in the bordered card and then
  // dropping the border when the agent went on was the bug.
  testWidgets('a running turn shows no final-answer card until it settles', (tester) async {
    const sid = 'running_turn';
    const intermediate = SessionEntry(
      id: 'a1',
      role: 'assistant',
      text: 'Checking the test results now.',
      timestamp: 2000,
      // The tool ran before the text, so nothing in this message follows it.
      metadata: {toolsBeforeTextKey: 1},
      toolCalls: [
        ToolExecutionState(
          toolCallId: 't1',
          toolName: 'bash',
          args: {'command': 'pnpm test'},
          output: 'ok',
          isRunning: false,
          startedAt: 1500,
          durationMs: 20,
        ),
      ],
    );
    final notifier = SessionStateNotifier(sid, null)
      ..state = const SessionState(
        sessionId: sid,
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        entries: [
          SessionEntry(id: 'u1', role: 'user', text: 'Why is it still blocked?', timestamp: 1000),
          intermediate,
        ],
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily(sid).overrideWith((ref) => notifier),
          stepGroupingSettingsProvider.overrideWith(
            (ref) => StepGroupingSettingsNotifier()..setMode(StepGroupingMode.always),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: TranscriptView(sessionId: sid)),
        ),
      ),
    );
    // A working turn shows an endless activity indicator, so pumpAndSettle would never return. One frame is all a
    // state change needs: the transcript rebuilds from the new session state in it.
    Future<void> settle() => tester.pump();

    Iterable<AssistantTurnFrame> cards() =>
        tester.widgetList<AssistantTurnFrame>(find.byType(AssistantTurnFrame)).where((frame) => frame.isCard);

    await settle();
    expect(cards(), isEmpty, reason: 'working between tool calls: the last message is not final yet');

    notifier.state = notifier.state.copyWith(streamingTextBlocks: {0: 'The failing test is'});
    await settle();
    expect(cards(), isEmpty, reason: 'the streaming tail is not the final answer');

    notifier.state = const SessionState(
      sessionId: sid,
      cwd: '/repo',
      agentStatus: AgentStatus.settled,
      entries: [
        SessionEntry(id: 'u1', role: 'user', text: 'Why is it still blocked?', timestamp: 1000),
        intermediate,
        SessionEntry(id: 'a2', role: 'assistant', text: 'One acceptance test is failing.', timestamp: 3000),
      ],
    );
    await settle();
    final answer = find.ancestor(
      of: find.text('One acceptance test is failing.', findRichText: true),
      matching: find.byType(AssistantTurnFrame),
    );
    expect(tester.widget<AssistantTurnFrame>(answer).isCard, isTrue, reason: 'the settled answer gets the card');
    expect(cards(), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
}
