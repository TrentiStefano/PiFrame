import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  Widget wrapTranscript({required SessionState state}) {
    return ProviderScope(
      overrides: [
        sessionStateFamily('s_timer_test').overrideWith(
          (ref) => SessionStateNotifier('s_timer_test', null)..state = state,
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: TranscriptView(sessionId: 's_timer_test'),
          ),
        ),
      ),
    );
  }

  group('Transcript message seconds counter and timeout display', () {
    testWidgets('displays seconds counter and timeout in assistant message taking >= 5s', (
      tester,
    ) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final entries = [
        SessionEntry(
          id: 'user_1',
          role: 'user',
          text: 'Run the database migration',
          timestamp: now - 12000, // 12 seconds ago
        ),
        SessionEntry(
          id: 'asst_1',
          role: 'assistant',
          text: 'Migration finished successfully.',
          timestamp: now - 3000, // took 9 seconds total
          toolCalls: const [
            ToolExecutionState(
              toolCallId: 't1',
              toolName: 'bash',
              args: {'command': 'pnpm db:migrate', 'timeout': 60},
              durationMs: 9000,
            ),
          ],
        ),
      ];

      final state = SessionState(
        sessionId: 's_timer_test',
        cwd: '/test',
        entries: entries,
        agentStatus: AgentStatus.settled,
      );

      await tester.pumpWidget(wrapTranscript(state: state));
      await tester.pumpAndSettle();

      // Assistant header timer should show 9s and timeout 60s
      final headerTimerFinder = find.byKey(const ValueKey('entry_timer_asst_1'));
      expect(headerTimerFinder, findsOneWidget);
      expect(find.descendant(of: headerTimerFinder, matching: find.text('9s')), findsOneWidget);
      expect(find.descendant(of: headerTimerFinder, matching: find.text(' (timeout: 60s)')), findsOneWidget);
    });

    testWidgets('does not show seconds counter if message took less than 5 seconds', (
      tester,
    ) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final entries = [
        SessionEntry(
          id: 'user_2',
          role: 'user',
          text: 'Quick question',
          timestamp: now - 3000, // 3 seconds ago
        ),
        SessionEntry(
          id: 'asst_2',
          role: 'assistant',
          text: 'Quick answer',
          timestamp: now - 1000, // took 2 seconds
        ),
      ];

      final state = SessionState(
        sessionId: 's_timer_test',
        cwd: '/test',
        entries: entries,
        agentStatus: AgentStatus.settled,
      );

      await tester.pumpWidget(wrapTranscript(state: state));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('entry_timer_asst_2')), findsNothing);
    });
  });
}
