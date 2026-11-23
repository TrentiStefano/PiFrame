import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Generates [count] turns. Each turn has 1 user prompt, [toolStepsPerTurn] tool
/// steps (which belong to grouped steps and do NOT count as agent answers), and 1
/// final assistant answer.
List<SessionEntry> _generateTurns({required int count, int toolStepsPerTurn = 5}) {
  final entries = <SessionEntry>[];
  for (var turn = 0; turn < count; turn++) {
    entries.add(SessionEntry(id: 'user_$turn', role: 'user', text: 'Prompt $turn', timestamp: turn * 1000));
    for (var step = 0; step < toolStepsPerTurn; step++) {
      entries.add(
        SessionEntry(
          id: 'step_${turn}_$step',
          role: 'assistant',
          text: '',
          toolCalls: [ToolExecutionState(toolCallId: 'call_${turn}_$step', toolName: 'execute_command')],
          timestamp: turn * 1000 + step + 1,
        ),
      );
    }
    entries.add(
      SessionEntry(
        id: 'answer_$turn',
        role: 'assistant',
        text: 'Agent Answer $turn',
        timestamp: turn * 1000 + toolStepsPerTurn + 2,
      ),
    );
  }
  return entries;
}

Future<void> _pump(WidgetTester tester, String sessionId, List<SessionEntry> entries) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        sessionStateFamily(sessionId).overrideWith(
          (ref) =>
              SessionStateNotifier(sessionId, null)
                ..state = SessionState(sessionId: sessionId, cwd: '/repo', entries: entries),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(body: TranscriptView(sessionId: sessionId)),
      ),
    ),
  );
}

void main() {
  testWidgets('history window keeps last 10 agent answers and does not count tool steps', (tester) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    // 15 turns: 15 user prompts, 75 tool steps, 15 agent answers = 105 entries total.
    // Last 10 answers are turns 5..14.
    // Turns 0..4 have 5 prompts + 25 tool steps + 5 answers = 35 entries hidden.
    await _pump(tester, 'window-10-answers', _generateTurns(count: 15, toolStepsPerTurn: 5));
    await tester.pumpAndSettle();

    final scrollable = find
        .descendant(of: find.byKey(const ValueKey('transcript-scroll')), matching: find.byType(Scrollable))
        .first;

    // Scroll to top so the load more button is fully in view
    await tester.drag(scrollable, const Offset(0, 10000));
    await tester.pumpAndSettle();

    final loadMore = find.textContaining('Load earlier messages');
    expect(find.textContaining('Load earlier messages (35 not shown)'), findsOneWidget);

    // The 10th-last turn's prompt ('Prompt 5') is loaded; earlier prompts (e.g. Prompt 4) are hidden.
    expect(find.textContaining('Prompt 5'), findsOneWidget);
    expect(find.textContaining('Prompt 4'), findsNothing);

    // Clicking load more loads 10 more answers, revealing all earlier entries
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.textContaining('non mostrati'), findsNothing);

    // Scroll to top to see Prompt 0
    await tester.drag(scrollable, const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prompt 0'), findsOneWidget);
  });

  testWidgets('tool steps do not unload user prompt when fewer than 10 answers exist', (tester) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    // 3 turns with 15 tool steps each (51 entries total).
    // Under the old raw-count limit (35 entries), 16 entries would be hidden,
    // unloading Prompt 0. Under answer-based windowing, because there are only 3
    // agent answers (< 10), all 51 entries remain loaded.
    final entries = _generateTurns(count: 3, toolStepsPerTurn: 15);
    await _pump(tester, 'window-few-answers', entries);
    await tester.pumpAndSettle();

    // No hidden entries banner exists
    expect(find.textContaining('non mostrati'), findsNothing);

    final scrollable = find
        .descendant(of: find.byKey(const ValueKey('transcript-scroll')), matching: find.byType(Scrollable))
        .first;

    // Scroll to the top to see Prompt 0
    await tester.drag(scrollable, const Offset(0, 10000));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prompt 0'), findsOneWidget);

    // Scroll to the bottom to see the latest answer
    await tester.drag(scrollable, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(find.textContaining('Agent Answer 2'), findsOneWidget);
  });
}
