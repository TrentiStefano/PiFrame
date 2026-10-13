import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/domain/session/agent_status.dart';
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_crust/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_crust/ui/shimmer_border.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

class _TestPinnedNotifier extends PinnedSessionsNotifier {
  _TestPinnedNotifier(Set<String> initial) : super() {
    state = initial;
  }
}

void main() {
  testWidgets('pinned session displays working indicator and shimmer when working', (
    tester,
  ) async {
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
          pinnedSessionsProvider.overrideWith(
            (ref) => _TestPinnedNotifier({'sess_pinned_1'}),
          ),
          activeSessionIdProvider.overrideWith((ref) => 'sess_pinned_1'),
          sessionStateFamily('sess_pinned_1').overrideWith((ref) => sessionNotifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [CrustTokens.dark],
          ),
          home: const Scaffold(body: SessionsSidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Pinned section should exist
    expect(find.text('FISSATE (1)'), findsOneWidget);
    expect(find.text('Core Engine Pinned'), findsOneWidget);

    // Initial non-working state: ShimmerBorder isActive is false
    final initialShimmers = tester.widgetList<ShimmerBorder>(find.byType(ShimmerBorder));
    expect(initialShimmers.any((s) => s.isActive), isFalse);

    // Set working to true on the pinned session
    sessionNotifier.state = sessionNotifier.state.copyWith(agentStatus: AgentStatus.working);
    await tester.pump(); // Start animations

    // Now ShimmerBorder should have isActive: true
    final activeShimmers = tester.widgetList<ShimmerBorder>(find.byType(ShimmerBorder));
    expect(activeShimmers.any((s) => s.isActive), isTrue);

    // Reset working to false
    sessionNotifier.state = sessionNotifier.state.copyWith(agentStatus: AgentStatus.settled);
    await tester.pump();

    final revertedShimmers = tester.widgetList<ShimmerBorder>(find.byType(ShimmerBorder));
    expect(revertedShimmers.any((s) => s.isActive), isFalse);
  });
}
