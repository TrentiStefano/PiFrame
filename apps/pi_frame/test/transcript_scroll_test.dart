import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  testWidgets('long transcript lazily builds turns and remains scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final entries = List.generate(
      80,
      (index) => SessionEntry(
        id: 'entry_$index',
        role: index.isEven ? 'user' : 'assistant',
        text:
            'Transcript entry $index\n${List.filled(index % 9 + 1, 'Variable height line').join('\n')}',
        timestamp: index,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily('scroll').overrideWith(
            (ref) => SessionStateNotifier('scroll', null)
              ..state = SessionState(
                sessionId: 'scroll',
                cwd: '/repo',
                entries: entries,
              ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: TranscriptView(sessionId: 'scroll')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollView = find.byKey(const ValueKey('transcript-scroll'));
    final controller = tester.widget<ListView>(scrollView).controller!;
    expect(controller.position.viewportDimension, greaterThan(0));
    expect(controller.position.maxScrollExtent, greaterThan(0));
    // Initial load lands on the latest message at the bottom
    expect(find.textContaining('Transcript entry 79'), findsOneWidget);
    // Older messages remain unloaded/scrolled off
    expect(find.textContaining('Transcript entry 0'), findsNothing);

    // Scroll up to reveal the load previous messages button
    final loadMoreFinder = find.textContaining('Carica messaggi precedenti');
    await tester.scrollUntilVisible(
      loadMoreFinder,
      -300,
      scrollable: find
          .descendant(of: scrollView, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    expect(loadMoreFinder, findsOneWidget);
  });
}
