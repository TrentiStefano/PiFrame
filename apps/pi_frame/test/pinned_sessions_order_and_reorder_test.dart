import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _TestPinnedNotifier extends PinnedSessionsNotifier {
  _TestPinnedNotifier(super.initial);
}

void main() {
  group('PinnedSessionsNotifier ordering and reordering unit tests', () {
    test('preserves insertion order and supports reorder and reorderById', () {
      final notifier = PinnedSessionsNotifier(['sess_a', 'sess_b', 'sess_c']);
      expect(notifier.state, ['sess_a', 'sess_b', 'sess_c']);

      // Reorder sess_a to index 1 (between b and c)
      // oldIndex = 0, newIndex = 2 (in Flutter onReorder contract)
      notifier.reorder(0, 2);
      expect(notifier.state, ['sess_b', 'sess_a', 'sess_c']);

      // Reorder sess_c to top
      notifier.reorder(2, 0);
      expect(notifier.state, ['sess_c', 'sess_b', 'sess_a']);

      // Reorder by ID: move sess_b to position 0
      notifier.reorderById('sess_b', 0);
      expect(notifier.state, ['sess_b', 'sess_c', 'sess_a']);

      // Reorder by ID: move sess_b to the bottom
      notifier.reorderById('sess_b', 2);
      expect(notifier.state, ['sess_c', 'sess_a', 'sess_b']);
    });
  });

  group('SessionsSidebar pinned sessions order stability and drag-to-reorder tests', () {
    testWidgets('pinned sessions preserve pinned order regardless of last activity or allSessions order', (
      tester,
    ) async {
      // allSessions has sess_2 first (e.g. because it had the most recent message)
      final mockSessions = [
        {
          'id': 'sess_2',
          'name': 'Session Two (Recent Answer)',
          'cwd': '/repo/app',
          'isActive': false,
          'lastMessagePreview': 'Latest answer just arrived',
          'updatedAt': 9999,
        },
        {
          'id': 'sess_1',
          'name': 'Session One (Old Answer)',
          'cwd': '/repo/app',
          'isActive': false,
          'lastMessagePreview': 'Old message from hours ago',
          'updatedAt': 1000,
        },
        {
          'id': 'sess_3',
          'name': 'Session Three',
          'cwd': '/repo/app',
          'isActive': false,
          'lastMessagePreview': 'Middle message',
          'updatedAt': 5000,
        },
      ];

      // Pinned order is explicitly sess_1, sess_2, sess_3
      final pinnedNotifier = _TestPinnedNotifier(['sess_1', 'sess_2', 'sess_3']);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            sessionListProvider.overrideWith((ref) => Future.value(mockSessions)),
            pinnedSessionsProvider.overrideWith((ref) => pinnedNotifier),
            activeSessionIdProvider.overrideWith((ref) => 'sess_1'),
            sessionStateFamily('sess_1').overrideWith(
              (ref) => SessionStateNotifier('sess_1', null)
                ..state = const SessionState(
                  sessionId: 'sess_1',
                  sessionName: 'Session One (Old Answer)',
                  cwd: '/repo/app',
                  agentStatus: AgentStatus.settled,
                  entries: [],
                ),
            ),
            sessionStateFamily('sess_2').overrideWith(
              (ref) => SessionStateNotifier('sess_2', null)
                ..state = const SessionState(
                  sessionId: 'sess_2',
                  sessionName: 'Session Two (Recent Answer)',
                  cwd: '/repo/app',
                  agentStatus: AgentStatus.settled,
                  entries: [],
                ),
            ),
            sessionStateFamily('sess_3').overrideWith(
              (ref) => SessionStateNotifier('sess_3', null)
                ..state = const SessionState(
                  sessionId: 'sess_3',
                  sessionName: 'Session Three',
                  cwd: '/repo/app',
                  agentStatus: AgentStatus.settled,
                  entries: [],
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(body: SessionsSidebar()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pinned header exists
      expect(find.text('FISSATE (3)'), findsOneWidget);

      // Verify that pinned session tiles appear in the pinned list order (sess_1, then sess_2, then sess_3)
      final sessionOneFinder = find.byKey(const ValueKey('pinned_session_sess_1'));
      final sessionTwoFinder = find.byKey(const ValueKey('pinned_session_sess_2'));
      final sessionThreeFinder = find.byKey(const ValueKey('pinned_session_sess_3'));

      expect(sessionOneFinder, findsOneWidget);
      expect(sessionTwoFinder, findsOneWidget);
      expect(sessionThreeFinder, findsOneWidget);

      final y1 = tester.getTopLeft(sessionOneFinder).dy;
      final y2 = tester.getTopLeft(sessionTwoFinder).dy;
      final y3 = tester.getTopLeft(sessionThreeFinder).dy;

      // session 1 is above session 2, which is above session 3
      expect(y1, lessThan(y2));
      expect(y2, lessThan(y3));
    });

    testWidgets('dragging pinned session holding with mouse reorders the pinned list and persists order', (
      tester,
    ) async {
      final mockSessions = [
        {
          'id': 'sess_alpha',
          'name': 'Alpha Session',
          'cwd': '/repo/app',
          'isActive': false,
        },
        {
          'id': 'sess_beta',
          'name': 'Beta Session',
          'cwd': '/repo/app',
          'isActive': false,
        },
      ];

      final pinnedNotifier = _TestPinnedNotifier(['sess_alpha', 'sess_beta']);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            sessionListProvider.overrideWith((ref) => Future.value(mockSessions)),
            pinnedSessionsProvider.overrideWith((ref) => pinnedNotifier),
            activeSessionIdProvider.overrideWith((ref) => 'sess_alpha'),
            sessionStateFamily('sess_alpha').overrideWith(
              (ref) => SessionStateNotifier('sess_alpha', null)
                ..state = const SessionState(
                  sessionId: 'sess_alpha',
                  cwd: '/repo/app',
                  entries: [],
                ),
            ),
            sessionStateFamily('sess_beta').overrideWith(
              (ref) => SessionStateNotifier('sess_beta', null)
                ..state = const SessionState(
                  sessionId: 'sess_beta',
                  cwd: '/repo/app',
                  entries: [],
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(body: SessionsSidebar()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(pinnedNotifier.state, ['sess_alpha', 'sess_beta']);

      // Press and hold on sess_alpha to initiate drag
      final alphaLocation = tester.getCenter(find.byKey(const ValueKey('pinned_session_sess_alpha')));
      final betaLocation = tester.getCenter(find.byKey(const ValueKey('pinned_session_sess_beta')));

      final gesture = await tester.startGesture(alphaLocation);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));

      // Move in increments so drag updates and reordering triggers
      final dyDistance = (betaLocation.dy - alphaLocation.dy) + 40;
      for (double step = 0; step <= dyDistance; step += 10) {
        await gesture.moveTo(Offset(alphaLocation.dx, alphaLocation.dy + step));
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Drop
      await gesture.up();
      await tester.pumpAndSettle();

      // Pinned list is now reordered: sess_beta first, then sess_alpha!
      expect(pinnedNotifier.state, ['sess_beta', 'sess_alpha']);
    });
  });
}
