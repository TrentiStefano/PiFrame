import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  testWidgets('expanded thinking block remains expanded when new entries arrive', (
    tester,
  ) async {
    final notifier = SessionStateNotifier('session_think', null)
      ..state = SessionState(
        sessionId: 'session_think',
        sessionName: 'Thinking Test',
        cwd: '/test/repo',
        entries: [
          SessionEntry(
            id: 'entry_user_1',
            role: 'user',
            text: 'Please think through this problem.',
            timestamp: 1,
          ),
          SessionEntry(
            id: 'entry_asst_1',
            role: 'assistant',
            text: 'Here is my reasoned answer.',
            thinking: 'Let me carefully evaluate option A versus option B.',
            timestamp: 2,
          ),
        ],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily('session_think').overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: TranscriptView(sessionId: 'session_think')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify thinking block header is present
    expect(find.text('Ragionamento'), findsOneWidget);
    // Initially collapsed: SelectableText body should not be rendered
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    // Tap the thinking block header to expand
    await tester.tap(find.text('Ragionamento'));
    await tester.pumpAndSettle();

    // Now SelectableText body should be visible with thinking details
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SelectableText),
        matching: find.text('Let me carefully evaluate option A versus option B.'),
      ),
      findsOneWidget,
    );

    // Simulate incoming new message while thinking block is expanded
    notifier.state = notifier.state.copyWith(
      entries: [
        ...notifier.state.entries,
        SessionEntry(
          id: 'entry_user_2',
          role: 'user',
          text: 'And what about the second part?',
          timestamp: 3,
        ),
        SessionEntry(
          id: 'entry_asst_2',
          role: 'assistant',
          text: 'Here is the response to the second part.',
          timestamp: 4,
        ),
      ],
    );
    await tester.pumpAndSettle();

    // Crucial check: thinking block of entry_asst_1 MUST REMAIN EXPANDED!
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SelectableText),
        matching: find.text('Let me carefully evaluate option A versus option B.'),
      ),
      findsOneWidget,
    );
    expect(find.text('And what about the second part?'), findsOneWidget);

    // Tapping header again collapses it
    await tester.tap(find.text('Ragionamento'));
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
  });
}
