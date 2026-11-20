import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/transcript/step_grouping_settings.dart';
import 'package:pi_frame/domain/session/transcript_grouping.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  Widget wrapTranscript({required SessionState state, bool groupSteps = true}) {
    return ProviderScope(
      overrides: [
        if (!groupSteps)
          stepGroupingSettingsProvider.overrideWith(
            (ref) => StepGroupingSettingsNotifier()..setMode(StepGroupingMode.off),
          ),
        sessionStateFamily('s_timer_test')
            .overrideWith((ref) => SessionStateNotifier('s_timer_test', null)..state = state),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(
          body: SizedBox(width: 800, height: 600, child: TranscriptView(sessionId: 's_timer_test')),
        ),
      ),
    );
  }

  group('Transcript message seconds counter and timeout display', () {
    testWidgets('shows elapsed message time without applying a command timeout to the message', (tester) async {
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

      // Grouping off, so the ToolCard (which owns the timeout) is built
      // instead of being folded into a collapsed step group.
      await tester.pumpWidget(wrapTranscript(state: state, groupSteps: false));
      await tester.pumpAndSettle();

      // The command timeout belongs to its ToolCard, not to the whole message.
      final headerTimerFinder = find.byKey(const ValueKey('entry_timer_asst_1'));
      expect(headerTimerFinder, findsOneWidget);
      expect(find.descendant(of: headerTimerFinder, matching: find.text('9s')), findsOneWidget);
      expect(find.descendant(of: headerTimerFinder, matching: find.textContaining('timeout')), findsNothing);
      expect(find.text(' / 60s'), findsOneWidget);
    });

    testWidgets('does not show seconds counter if message took less than 5 seconds', (tester) async {
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

    testWidgets('marks an aborted assistant turn with a neutral Interrotto tag', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final entries = [
        SessionEntry(id: 'user_a', role: 'user', text: 'Scrivi una lunga risposta', timestamp: now - 9000),
        SessionEntry(
          id: 'asst_aborted',
          role: 'assistant',
          text: 'Risposta parziale...',
          timestamp: now - 2000,
          metadata: const {'stopReason': 'aborted'},
        ),
        SessionEntry(id: 'user_b', role: 'user', text: 'Continua', timestamp: now - 1500),
        SessionEntry(
          id: 'asst_done',
          role: 'assistant',
          text: 'Risposta completa.',
          timestamp: now - 1000,
          metadata: const {'stopReason': 'stop'},
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

      final abortedTagFinder = find.byKey(const ValueKey('entry_aborted_asst_aborted'));
      expect(abortedTagFinder, findsOneWidget);
      expect(find.descendant(of: abortedTagFinder, matching: find.text('Interrotto')), findsOneWidget);
      expect(find.byKey(const ValueKey('entry_aborted_asst_done')), findsNothing);
    });
  });
}
