import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/features/transcript/transcript_view.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

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
            extensions: const [CrustTokens.dark],
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
    expect(find.textContaining('Transcript entry 79'), findsNothing);

    final lastEntryFinder = find.textContaining('Transcript entry 79');
    await tester.scrollUntilVisible(
      lastEntryFinder,
      400,
      scrollable: find
          .descendant(of: scrollView, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    final lastEntry = tester.getRect(lastEntryFinder.first);
    final viewport = tester.getRect(scrollView);
    expect(lastEntry.bottom, lessThanOrEqualTo(viewport.bottom + 1));
    expect(lastEntry.top, greaterThanOrEqualTo(viewport.top - 1));
  });
}
