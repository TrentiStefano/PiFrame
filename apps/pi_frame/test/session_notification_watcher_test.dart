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
import 'package:pi_frame/features/transcript/subagents_provider.dart';
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
  _TestPinnedNotifier(super.initial);
}

class _MockSubagentsNotifier extends StateNotifier<List<SubagentItem>>
    implements SubagentsNotifier {
  _MockSubagentsNotifier([List<SubagentItem>? initial]) : super(initial ?? []);

  void updateState(List<SubagentItem> items) {
    state = items;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

  testWidgets('does not trigger completion notification when transitioning to retrying or compacting', (
    tester,
  ) async {
    final mockService = MockDesktopNotificationService();
    final notifier = SessionStateNotifier('sess_retry', null)
      ..state = SessionState(
        sessionId: 'sess_retry',
        sessionName: 'Retry Session',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        entries: [
          SessionEntry(
            id: 'asst_1',
            role: 'assistant',
            text: 'I will retry in 5 seconds...',
            timestamp: 1,
          ),
        ],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopNotificationServiceProvider.overrideWithValue(mockService),
          appFocusProvider.overrideWith((ref) => false), // Unfocused
          notificationsEnabledProvider.overrideWith((ref) => true),
          activeSessionIdProvider.overrideWith((ref) => 'sess_retry'),
          sessionStateFamily('sess_retry').overrideWith((ref) => notifier),
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

    // Agent transitions to retrying - must NOT trigger notification
    notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.retrying);
    await tester.pumpAndSettle();
    expect(mockService.sent, isEmpty);

    // Agent transitions to compacting - must NOT trigger notification
    notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.compacting);
    await tester.pumpAndSettle();
    expect(mockService.sent, isEmpty);

    // Agent transitions back to working
    notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.working);
    await tester.pumpAndSettle();
    expect(mockService.sent, isEmpty);

    // Now agent truly settles with final answer
    notifier.state = notifier.state.copyWith(
      agentStatus: AgentStatus.settled,
      entries: [
        ...notifier.state.entries,
        SessionEntry(
          id: 'asst_final',
          role: 'assistant',
          text: 'Final response after retry.',
          timestamp: 2,
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(mockService.sent, hasLength(1));
    expect(mockService.sent.first.title, contains('Risposta completata'));
    expect(mockService.sent.first.body, contains('Final response after retry.'));
  });

  testWidgets('does not trigger completion notification while subagents are running', (
    tester,
  ) async {
    final mockService = MockDesktopNotificationService();
    final sessionNotifier = SessionStateNotifier('sess_subagents', null)
      ..state = SessionState(
        sessionId: 'sess_subagents',
        sessionName: 'Subagents Session',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        entries: [],
      );

    late _MockSubagentsNotifier subagentsNotifier;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopNotificationServiceProvider.overrideWithValue(mockService),
          appFocusProvider.overrideWith((ref) => false), // Unfocused
          notificationsEnabledProvider.overrideWith((ref) => true),
          activeSessionIdProvider.overrideWith((ref) => 'sess_subagents'),
          sessionStateFamily('sess_subagents').overrideWith((ref) => sessionNotifier),
          subagentsFamily('sess_subagents').overrideWith((ref) {
            subagentsNotifier = _MockSubagentsNotifier([
              const SubagentItem(
                id: 'sub_1',
                name: 'Worker 1',
                status: 'running',
              ),
            ]);
            return subagentsNotifier;
          }),
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

    // Main session settles its initial turn, but subagent is still running
    sessionNotifier.state = sessionNotifier.state.copyWith(
      agentStatus: AgentStatus.settled,
      entries: [
        SessionEntry(
          id: 'asst_spawn',
          role: 'assistant',
          text: 'Launched background workers to analyze codebase.',
          timestamp: 1,
        ),
      ],
    );
    await tester.pumpAndSettle();

    // MUST NOT notify because subagent is still running!
    expect(mockService.sent, isEmpty);

    // Subagent completes!
    subagentsNotifier.updateState([
      const SubagentItem(
        id: 'sub_1',
        name: 'Worker 1',
        status: 'completed',
      ),
    ]);
    await tester.pumpAndSettle();

    // Now notification fires because all work has settled
    expect(mockService.sent, hasLength(1));
    expect(mockService.sent.first.title, contains('Risposta completata'));
    expect(mockService.sent.first.body, contains('Launched background workers'));
  });

  testWidgets('does not trigger notification for existing entries when watcher is mounted', (
    tester,
  ) async {
    final mockService = MockDesktopNotificationService();
    final notifier = SessionStateNotifier('sess_existing', null)
      ..state = SessionState(
        sessionId: 'sess_existing',
        sessionName: 'Pre-existing Session',
        cwd: '/repo',
        agentStatus: AgentStatus.settled,
        entries: [
          SessionEntry(
            id: 'old_asst_1',
            role: 'assistant',
            text: 'This answer was completed yesterday.',
            timestamp: 1,
          ),
        ],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopNotificationServiceProvider.overrideWithValue(mockService),
          appFocusProvider.overrideWith((ref) => false),
          notificationsEnabledProvider.overrideWith((ref) => true),
          activeSessionIdProvider.overrideWith((ref) => 'sess_existing'),
          sessionStateFamily('sess_existing').overrideWith((ref) => notifier),
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

    // Trigger state change (e.g. queue or stats change) while settled
    notifier.state = notifier.state.copyWith(steeringQueue: const []);
    await tester.pumpAndSettle();

    // Should NOT notify for old_asst_1
    expect(mockService.sent, isEmpty);
  });
}
