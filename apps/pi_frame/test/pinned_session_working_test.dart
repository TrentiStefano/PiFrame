import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_frame/ui/shimmer_border.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _TestPinnedNotifier extends PinnedSessionsNotifier {
  _TestPinnedNotifier(super.initial);
}

void main() {
  testWidgets('pinned session displays working indicator and shimmer when working', (tester) async {
    final mockSessions = [
      {
        'id': 'sess_pinned_1',
        'name': 'Core Engine Pinned',
        'cwd': '/projects/core',
        'isActive': false,
        'lastMessagePreview': 'Running tasks...',
      },
    ];

    final sessionNotifier = SessionStateNotifier('sess_pinned_1', null)
      ..state = SessionState(
        sessionId: 'sess_pinned_1',
        sessionName: 'Core Engine Pinned',
        cwd: '/projects/core',
        agentStatus: AgentStatus.settled,
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionListProvider.overrideWith((ref) => Future.value(mockSessions)),
          pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({'sess_pinned_1'})),
          activeSessionIdProvider.overrideWith((ref) => 'sess_pinned_1'),
          sessionStateFamily('sess_pinned_1').overrideWith((ref) => sessionNotifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: SessionsSidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Pinned section should exist
    expect(find.text('PINNED (1)'), findsOneWidget);
    // Shown in the pinned section, and again under its repository, which is the
    // active one and therefore expanded by default.
    expect(find.text('Core Engine Pinned'), findsNWidgets(2));

    // Sessions cards should never have ShimmerBorder
    expect(find.byType(ShimmerBorder), findsNothing);

    bool hasWorkingBorder() {
      final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      return boxes.any((b) {
        final dec = b.decoration;
        if (dec is BoxDecoration && dec.border != null) {
          return dec.border!.top.color == FrameTokens.dark.agentWorking.withValues(alpha: 0.7);
        }
        return false;
      });
    }

    // Initial non-working state: no working border
    expect(hasWorkingBorder(), isFalse);

    // Set working to true on the pinned session
    sessionNotifier.state = sessionNotifier.state.copyWith(agentStatus: AgentStatus.working);
    await tester.pump();

    // Now the working border and spinner are shown on session rows, with no shimmering
    expect(hasWorkingBorder(), isTrue);
    expect(find.byKey(const ValueKey('session-working-spinner')), findsWidgets);
    expect(find.byType(ShimmerBorder), findsNothing);

    // The pinned section header itself must NOT show any redundant loading animation
    final pinnedHeader = find.ancestor(of: find.text('PINNED (1)'), matching: find.byType(Row));
    expect(
      find.descendant(of: pinnedHeader, matching: find.byKey(const ValueKey('session-working-spinner'))),
      findsNothing,
    );

    // Reset working to false
    sessionNotifier.state = sessionNotifier.state.copyWith(agentStatus: AgentStatus.settled);
    await tester.pump();

    // Working border disappears
    expect(hasWorkingBorder(), isFalse);
  });
}
