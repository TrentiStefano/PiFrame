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
import 'package:pi_frame/features/transcript/workflows_provider.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class MockDesktopNotificationService extends DesktopNotificationService {
  MockDesktopNotificationService() : super.forTesting();

  final List<({String title, String body, String? sessionId})> sent = [];
  final List<DesktopIndicatorStatus> indicatorHistory = [];

  @override
  bool get isSupported => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkIsAppFocused(bool fallbackState) async => fallbackState;

  @override
  Future<void> updateIndicatorStatus(DesktopIndicatorStatus status) async {
    if (indicatorStatus == status) return;
    indicatorHistory.add(status);
    await super.updateIndicatorStatus(status);
  }

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
    await tester.pump(finalAnswerQuietPeriod);

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
    await tester.pump(finalAnswerQuietPeriod);

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
    await tester.pump(finalAnswerQuietPeriod);

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
    await tester.pump(finalAnswerQuietPeriod);

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
    await tester.pump(finalAnswerQuietPeriod);

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

  group('only the final answer notifies', () {
    final focused = StateProvider<bool>((ref) => false);
    final workflowRunning = StateProvider<bool>((ref) => false);

    Future<(MockDesktopNotificationService, SessionStateNotifier, ProviderContainer)> pump(
      WidgetTester tester,
      String sid,
    ) async {
      final service = MockDesktopNotificationService();
      final notifier = SessionStateNotifier(sid, null)
        ..state = SessionState(
          sessionId: sid,
          sessionName: 'Final answer',
          cwd: '/repo',
          agentStatus: AgentStatus.settled,
          entries: const [],
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopNotificationServiceProvider.overrideWithValue(service),
            appFocusProvider.overrideWith((ref) => ref.watch(focused)),
            notificationsEnabledProvider.overrideWith((ref) => true),
            activeSessionIdProvider.overrideWith((ref) => sid),
            sessionStateFamily(sid).overrideWith((ref) => notifier),
            subagentsFamily(sid).overrideWith((ref) => _MockSubagentsNotifier()),
            backgroundAgentsRunningProvider(sid).overrideWith((ref) => ref.watch(workflowRunning)),
            pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({})),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(body: SessionNotificationWatcher()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(SessionNotificationWatcher)));
      return (service, notifier, container);
    }

    SessionEntry answer(String id, String text, {List<ToolExecutionState> tools = const []}) =>
        SessionEntry(id: id, role: 'assistant', text: text, toolCalls: tools, timestamp: 2);

    testWidgets('an answer between steps does not notify; the final one does, once', (tester) async {
      final (service, notifier, _) = await pump(tester, 'steps');
      notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.working);
      await tester.pump();

      // A brief "settled" between steps (question answered, compaction, next turn).
      notifier.state = notifier.state.copyWith(
        agentStatus: AgentStatus.settled,
        entries: [answer('mid', 'Reading the files first.')],
      );
      await tester.pump(finalAnswerQuietPeriod ~/ 2);
      notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.working);
      await tester.pump(finalAnswerQuietPeriod * 2);
      expect(service.sent, isEmpty);

      notifier.state = notifier.state.copyWith(
        agentStatus: AgentStatus.settled,
        entries: [answer('mid', 'Reading the files first.'), answer('final', 'All done: tests pass.')],
      );
      await tester.pump(finalAnswerQuietPeriod);
      await tester.pumpAndSettle();
      expect(service.sent, hasLength(1));
      expect(service.sent.single.body, 'All done: tests pass.');
    });

    testWidgets('a running workflow keeps the answer from counting as final', (tester) async {
      final (service, notifier, container) = await pump(tester, 'workflow');
      notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.working);
      await tester.pump();
      container.read(workflowRunning.notifier).state = true;
      notifier.state = notifier.state.copyWith(
        agentStatus: AgentStatus.settled,
        entries: [answer('started', 'Workflow started in the background.')],
      );
      await tester.pump(finalAnswerQuietPeriod * 2);
      expect(service.sent, isEmpty);

      container.read(workflowRunning.notifier).state = false;
      notifier.state = notifier.state.copyWith(
        entries: [answer('started', 'Workflow started in the background.'), answer('done', 'Workflow finished.')],
      );
      await tester.pump(finalAnswerQuietPeriod);
      await tester.pumpAndSettle();
      expect(service.sent.map((n) => n.body), ['Workflow finished.']);
      container.read(workflowRunning.notifier).state = false;
    });

    testWidgets('a run started while PiFrame was focused still notifies if it ends unfocused', (tester) async {
      final (service, notifier, container) = await pump(tester, 'focus');
      container.read(focused.notifier).state = true;
      notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.working);
      await tester.pump();
      container.read(focused.notifier).state = false;
      notifier.state = notifier.state.copyWith(
        agentStatus: AgentStatus.settled,
        entries: [answer('done', 'Finished while you were away.')],
      );
      await tester.pump(finalAnswerQuietPeriod);
      await tester.pumpAndSettle();
      expect(service.sent.map((n) => n.body), ['Finished while you were away.']);
    });

    testWidgets('desktop indicator updates working -> unread -> idle on focus', (tester) async {
      final (service, notifier, container) = await pump(tester, 'indicator_flow');
      container.read(focused.notifier).state = false;
      expect(service.indicatorHistory, isEmpty);

      // 1. Session begins working
      notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.working);
      await tester.pump();
      expect(service.indicatorHistory, [DesktopIndicatorStatus.working]);

      // 2. Agent finishes answer while unfocused
      notifier.state = notifier.state.copyWith(
        agentStatus: AgentStatus.settled,
        entries: [answer('a1', 'Done working on your task.')],
      );
      await tester.pump(finalAnswerQuietPeriod);
      await tester.pumpAndSettle();
      expect(
        service.indicatorHistory,
        [DesktopIndicatorStatus.working, DesktopIndicatorStatus.unread],
      );

      // 3. User focuses the app
      container.read(focused.notifier).state = true;
      await tester.pump();
      expect(
        service.indicatorHistory,
        [
          DesktopIndicatorStatus.working,
          DesktopIndicatorStatus.unread,
          DesktopIndicatorStatus.idle,
        ],
      );
    });

    testWidgets('desktop indicator transitions working -> idle when finished while focused', (tester) async {
      final (service, notifier, container) = await pump(tester, 'indicator_focused');
      container.read(focused.notifier).state = true;

      // Agent starts working
      notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.working);
      await tester.pump();
      expect(service.indicatorHistory, [DesktopIndicatorStatus.working]);

      // Agent completes while user is viewing the app
      notifier.state = notifier.state.copyWith(
        agentStatus: AgentStatus.settled,
        entries: [answer('a2', 'Finished in front of user.')],
      );
      await tester.pump(finalAnswerQuietPeriod);
      await tester.pumpAndSettle();
      expect(
        service.indicatorHistory,
        [DesktopIndicatorStatus.working, DesktopIndicatorStatus.idle],
      );
    });
  });

  test('finalAnswerEntry skips notifications and rejects a hand-off to a tool', () {
    const tool = ToolExecutionState(toolCallId: 't', toolName: 'bash', args: {}, output: '');
    expect(
      finalAnswerEntry(const [
        SessionEntry(id: 'a', role: 'assistant', text: 'Final words.', timestamp: 1),
        SessionEntry(id: 'n', role: 'assistant', text: '<task-notification>x</task-notification>', timestamp: 2),
      ])?.id,
      'a',
    );
    expect(
      finalAnswerEntry(const [
        SessionEntry(id: 'b', role: 'assistant', text: 'Let me check.', toolCalls: [tool], timestamp: 1),
      ]),
      isNull,
    );
    expect(finalAnswerEntry(const [SessionEntry(id: 'c', role: 'assistant', text: ' ', timestamp: 1)]), isNull);
  });
}
