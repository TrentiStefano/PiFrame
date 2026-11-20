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
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

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
}
