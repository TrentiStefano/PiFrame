import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Six prompts, each followed by 12 assistant steps. The count-based window
/// (35 entries) would start inside the 4th turn and show only 2 prompts.
List<SessionEntry> _turns() {
  final entries = <SessionEntry>[];
  for (var turn = 0; turn < 6; turn++) {
    entries.add(
      SessionEntry(
        id: 'user_$turn',
        role: 'user',
        text: 'Prompt $turn',
        timestamp: turn * 100,
      ),
    );
    for (var step = 0; step < 12; step++) {
      entries.add(
        SessionEntry(
          id: 'step_${turn}_$step',
          role: 'assistant',
          text: 'Step $turn.$step',
          timestamp: turn * 100 + step + 1,
        ),
      );
    }
  }
  return entries;
}

Future<void> _pump(WidgetTester tester, String sessionId, List<SessionEntry> entries) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        sessionStateFamily(sessionId).overrideWith(
          (ref) => SessionStateNotifier(sessionId, null)
            ..state = SessionState(
              sessionId: sessionId,
              cwd: '/repo',
              entries: entries,
            ),
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
  testWidgets(
    'history window reaches the 5th-last user prompt inside a long turn',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await _pump(tester, 'window-long', _turns());
      await tester.pumpAndSettle();

      // 78 entries, 5th-last prompt is 'Prompt 1' at index 13, so 13 hidden.
      final loadMore = find.textContaining('Carica messaggi precedenti');
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('transcript-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(loadMore, -300, scrollable: scrollable);
      expect(
        find.textContaining('Carica messaggi precedenti (13 non mostrati)'),
        findsOneWidget,
      );
      // The 5th-last prompt must be on screen, not just the last two.
      expect(find.textContaining('Prompt 1'), findsOneWidget);
      expect(find.textContaining('Prompt 0'), findsNothing);
    },
  );

  testWidgets('history window keeps every prompt when fewer than 5 exist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final entries = _turns().take(2).toList();
    await _pump(tester, 'window-short', entries);
    await tester.pumpAndSettle();

    expect(find.textContaining('non mostrati'), findsNothing);
    expect(find.textContaining('Prompt 0'), findsOneWidget);
  });
}
