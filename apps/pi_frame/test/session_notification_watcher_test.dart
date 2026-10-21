import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/notifications/desktop_notification_service.dart';
import 'package:pi_frame/data/notifications/notification_providers.dart';
import 'package:pi_frame/data/notifications/session_notification_watcher.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class MockDesktopNotificationService extends DesktopNotificationService {
  MockDesktopNotificationService() : super.forTesting();

  final List<({String title, String body, String? sessionId})> sent = [];

  @override
  bool get isSupported => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkIsAppFocused(bool fallbackState) async => fallbackState;

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? sessionId,
  }) async {
    sent.add((title: title, body: body, sessionId: sessionId));
  }
}

class _TestPinnedNotifier extends PinnedSessionsNotifier {
  _TestPinnedNotifier(Set<String> initial) : super() {
    state = initial;
  }
}

void main() {
  testWidgets('triggers system notification when agent completes answer while app unfocused', (
    tester,
  ) async {
    final mockService = MockDesktopNotificationService();
    final notifier = SessionStateNotifier('sess_notif_1', null)
      ..state = SessionState(
        sessionId: 'sess_notif_1',
        sessionName: 'Notification Test Session',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopNotificationServiceProvider.overrideWithValue(mockService),
          appFocusProvider.overrideWith((ref) => false), // App is NOT focused
          notificationsEnabledProvider.overrideWith((ref) => true),
          activeSessionIdProvider.overrideWith((ref) => 'sess_notif_1'),
          sessionStateFamily('sess_notif_1').overrideWith((ref) => notifier),
          pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({})),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: SessionNotificationWatcher()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(mockService.sent, isEmpty);

    // Agent finishes answer
    notifier.state = notifier.state.copyWith(
      agentStatus: AgentStatus.settled,
      entries: [
        SessionEntry(
          id: 'user_prompt',
          role: 'user',
          text: 'Can you solve this issue?',
          timestamp: 1,
        ),
        SessionEntry(
          id: 'asst_reply',
          role: 'assistant',
          text: 'I have finished writing the patch and tests.',
          timestamp: 2,
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(mockService.sent, hasLength(1));
    expect(mockService.sent.first.title, contains('Risposta completata'));
    expect(mockService.sent.first.body, contains('I have finished writing the patch and tests.'));
    expect(mockService.sent.first.sessionId, 'sess_notif_1');
  });

  testWidgets('suppresses notification when app is focused', (
    tester,
  ) async {
    final mockService = MockDesktopNotificationService();
    final notifier = SessionStateNotifier('sess_notif_2', null)
      ..state = SessionState(
        sessionId: 'sess_notif_2',
        sessionName: 'Focused Session',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopNotificationServiceProvider.overrideWithValue(mockService),
          appFocusProvider.overrideWith((ref) => true), // App IS focused
          notificationsEnabledProvider.overrideWith((ref) => true),
          activeSessionIdProvider.overrideWith((ref) => 'sess_notif_2'),
          sessionStateFamily('sess_notif_2').overrideWith((ref) => notifier),
          pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({})),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: SessionNotificationWatcher()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    notifier.state = notifier.state.copyWith(
      agentStatus: AgentStatus.idle,
      entries: [
        SessionEntry(
          id: 'asst_reply_2',
          role: 'assistant',
          text: 'Finished answer while user is looking.',
          timestamp: 1,
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(mockService.sent, isEmpty);
  });

  testWidgets('triggers notification when interactive UI request requires user attention', (
    tester,
  ) async {
    final mockService = MockDesktopNotificationService();
    final notifier = SessionStateNotifier('sess_notif_3', null)
      ..state = SessionState(
        sessionId: 'sess_notif_3',
        sessionName: 'Interactive Session',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopNotificationServiceProvider.overrideWithValue(mockService),
          appFocusProvider.overrideWith((ref) => false), // Unfocused
          notificationsEnabledProvider.overrideWith((ref) => true),
          activeSessionIdProvider.overrideWith((ref) => 'sess_notif_3'),
          sessionStateFamily('sess_notif_3').overrideWith((ref) => notifier),
          pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({})),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: SessionNotificationWatcher()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    notifier.state = notifier.state.copyWith(
      pendingUiRequests: [
        {
          'requestId': 'req_confirm_42',
          'method': 'confirm',
          'dialog': true,
          'title': 'Conferma esecuzione comando',
          'message': 'Vuoi procedere con il commit?',
        },
      ],
    );
    await tester.pumpAndSettle();

    expect(mockService.sent, hasLength(1));
    expect(mockService.sent.first.title, contains('Richiesta attenzione'));
    expect(mockService.sent.first.body, contains('Conferma esecuzione comando'));
    expect(mockService.sent.first.sessionId, 'sess_notif_3');
  });

  testWidgets('clicking notification navigates to the session', (
    tester,
  ) async {
    final mockService = MockDesktopNotificationService();
    final container = ProviderContainer(
      overrides: [
        desktopNotificationServiceProvider.overrideWithValue(mockService),
        activeSessionIdProvider.overrideWith((ref) => 'initial_sess'),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: SessionNotificationWatcher()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(activeSessionIdProvider), 'initial_sess');

    // Simulate clicking a notification for target_sess
    mockService.onNotificationClicked?.call('target_sess');
    await tester.pumpAndSettle();

    expect(container.read(activeSessionIdProvider), 'target_sess');
  });
}
