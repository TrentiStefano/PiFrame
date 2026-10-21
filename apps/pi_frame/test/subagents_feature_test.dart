import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/removed_repos_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_frame/features/transcript/subagent_panel.dart';
import 'package:pi_frame/features/transcript/subagents_provider.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _TestPinnedNotifier extends PinnedSessionsNotifier {
  _TestPinnedNotifier(Set<String> initial) : super() {
    state = initial;
  }
}

class _TestRemovedNotifier extends RemovedReposNotifier {
  _TestRemovedNotifier(Set<String> initial) : super() {
    state = initial;
  }
}

class _MockSubagentsNotifier extends SubagentsNotifier {
  _MockSubagentsNotifier(super.ref, super.sessionId, List<SubagentItem> initial) {
    state = initial;
  }
}

void main() {
  group('Subagents Feature & Subsession Filtering Tests', () {
    testWidgets('Subagent sessions are filtered out of the sessions sidebar', (tester) async {
      final mockSessions = [
        {
          'id': 'sess_main_1',
          'name': 'Main User Session',
          'cwd': 'C:/projects/app',
          'isActive': true,
          'lastMessagePreview': 'Hello',
        },
        {
          'id': 'subagent_01',
          'name': 'reviewer#123',
          'cwd': 'C:/projects/app',
          'parentSession': 'sess_main_1.jsonl',
          'isSubsession': true,
          'isActive': true,
          'lastMessagePreview': 'Subagent doing review',
        },
        {
          'id': 'sess_worker_2',
          'name': 'worker#55',
          'cwd': 'C:/projects/app',
          'isActive': false,
          'lastMessagePreview': 'Background worker',
        },
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            sessionListProvider.overrideWith(
              (ref) => Future.value(mockSessions),
            ),
            pinnedSessionsProvider.overrideWith(
              (ref) => _TestPinnedNotifier({}),
            ),
            removedReposProvider.overrideWith(
              (ref) => _TestRemovedNotifier({}),
            ),
            activeSessionIdProvider.overrideWith((ref) => 'sess_main_1'),
            sessionStateFamily('sess_main_1').overrideWith(
              (ref) => SessionStateNotifier('sess_main_1', null)
                ..state = const SessionState(
                  sessionId: 'sess_main_1',
                  cwd: 'C:/projects/app',
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: SessionsSidebar(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Folder 'app' exists. Tap to expand it and reveal sessions.
      expect(find.text('app'), findsOneWidget);
      await tester.tap(find.text('app'));
      await tester.pumpAndSettle();

      // Main session should appear in the pane
      expect(find.text('Main User Session'), findsOneWidget);

      // Subagent sessions should NOT appear in the pane
      expect(find.text('reviewer#123'), findsNothing);
      expect(find.text('worker#55'), findsNothing);
    });

    testWidgets('SubagentsPopDown renders expandable window with name, model, cost and output', (tester) async {
      final subagents = [
        const SubagentItem(
          id: 'sub_explore_1',
          name: 'Explore Agent',
          model: 'gpt-6-luna',
          cost: 0.0175,
          output: 'Found 4 files matching auth query:\n- auth.dart\n- user.dart',
          status: 'running',
          description: 'Search for authentication files',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subagentsFamily('test_session').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'test_session', subagents),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: SubagentsPopDown(
                sessionId: 'test_session',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header and subagent details
      expect(find.textContaining('Subagenti (1)'), findsOneWidget);
      expect(find.text('Explore Agent'), findsOneWidget);
      expect(find.text('gpt-6-luna'), findsOneWidget);
      expect(find.text('\$0.0175'), findsOneWidget);
      expect(find.textContaining('In corso'), findsWidgets);

      // Output should be displayed
      expect(find.textContaining('Found 4 files matching auth query:'), findsOneWidget);
    });

    testWidgets('Steer button reveals text input and stop button updates status', (tester) async {
      final subagents = [
        const SubagentItem(
          id: 'sub_agent_steerable',
          name: 'Test Delegate',
          model: 'claude-3-5-sonnet',
          cost: 0.0080,
          output: 'Working on tasks...',
          status: 'running',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subagentsFamily('test_session').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'test_session', subagents),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: SubagentsPopDown(
                sessionId: 'test_session',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Steering box should not be visible initially
      expect(find.byKey(const ValueKey('subagent-steer-box-sub_agent_steerable')), findsNothing);

      // Click Steer button
      final steerBtn = find.byKey(const ValueKey('subagent-steer-btn-sub_agent_steerable'));
      expect(steerBtn, findsOneWidget);
      await tester.tap(steerBtn);
      await tester.pumpAndSettle();

      // Steering box should appear with text field and Invia button
      expect(find.byKey(const ValueKey('subagent-steer-box-sub_agent_steerable')), findsOneWidget);
      expect(find.byKey(const ValueKey('subagent-steer-input-sub_agent_steerable')), findsOneWidget);
      expect(find.byKey(const ValueKey('subagent-steer-send-sub_agent_steerable')), findsOneWidget);

      // Enter steering text and send
      await tester.enterText(
        find.byKey(const ValueKey('subagent-steer-input-sub_agent_steerable')),
        'Focus on unit tests first',
      );
      await tester.tap(find.byKey(const ValueKey('subagent-steer-send-sub_agent_steerable')));
      await tester.pumpAndSettle();

      // Steering box closes and output updates with steer indicator
      expect(find.byKey(const ValueKey('subagent-steer-box-sub_agent_steerable')), findsNothing);
      expect(find.textContaining('Focus on unit tests first'), findsOneWidget);

      // Click Stop button
      final stopBtn = find.byKey(const ValueKey('subagent-stop-btn-sub_agent_steerable'));
      expect(stopBtn, findsOneWidget);
      await tester.tap(stopBtn);
      await tester.pumpAndSettle();

      // Status should be stopped
      expect(find.textContaining('Fermato'), findsOneWidget);
    });

    testWidgets('TranscriptView displays subagents popdown banner and toggle chip', (tester) async {
      final subagents = [
        const SubagentItem(
          id: 'sub_agent_active',
          name: 'Active Subagent',
          model: 'haiku',
          cost: 0.002,
          output: 'Streaming output...',
          status: 'running',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('sess_chat_1').overrideWith(
              (ref) => SessionStateNotifier('sess_chat_1', null)
                ..state = const SessionState(
                  sessionId: 'sess_chat_1',
                  sessionName: 'Chat with Subagents',
                  cwd: 'C:/projects/app',
                  agentStatus: AgentStatus.settled,
                ),
            ),
            subagentsFamily('sess_chat_1').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'sess_chat_1', subagents),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: TranscriptView(
                sessionId: 'sess_chat_1',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Subagents header chip should be visible
      expect(find.byKey(const ValueKey('subagents-header-chip')), findsOneWidget);
      expect(find.text('Subagenti (1)'), findsWidgets);

      // SubagentsPopDown should be displayed by default
      expect(find.byKey(const ValueKey('subagents-popdown-panel')), findsOneWidget);
      expect(find.text('Active Subagent'), findsOneWidget);

      // Click close button on popdown
      await tester.tap(find.byKey(const ValueKey('subagents-popdown-close-btn')));
      await tester.pumpAndSettle();

      // Popdown should be collapsed
      expect(find.byKey(const ValueKey('subagents-popdown-panel')), findsNothing);

      // Tap header chip to pop it down again
      await tester.tap(find.byKey(const ValueKey('subagents-header-chip')));
      await tester.pumpAndSettle();

      // Popdown is visible again
      expect(find.byKey(const ValueKey('subagents-popdown-panel')), findsOneWidget);
    });
  });
}
