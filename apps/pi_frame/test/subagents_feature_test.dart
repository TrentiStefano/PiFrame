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
      expect(find.text('\$0.0175'), findsNWidgets(2));
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

      // Popdown should be collapsed and reveal the book tab
      expect(find.byKey(const ValueKey('subagents-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('subagents-book-tab')), findsOneWidget);

      // Tap book tab to expand it again with smooth sliding animation
      await tester.tap(find.byKey(const ValueKey('subagents-book-tab')));
      await tester.pumpAndSettle();

      // Popdown is visible again
      expect(find.byKey(const ValueKey('subagents-popdown-panel')), findsOneWidget);
    });

    testWidgets('Subagent task does not have user checkmark and crosses out title when completed', (tester) async {
      final subagents = [
        const SubagentItem(
          id: 'sub_completed_task',
          name: 'Completed Agent Task',
          model: 'claude-3-5-sonnet',
          cost: 0.005,
          status: 'completed',
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
              body: SubagentsPopDown(sessionId: 'test_session'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Ensure no Checkbox exists (user should not be able to checkmark subagent tasks)
      expect(find.byType(Checkbox), findsNothing);

      // Verify model used is displayed
      expect(find.text('claude-3-5-sonnet'), findsOneWidget);

      // Find the text widget for completed agent task and verify strikethrough decoration
      final titleFinder = find.text('Completed Agent Task');
      expect(titleFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(titleFinder);
      expect(textWidget.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('Full session cost card and multi-tier dropdown popup', (tester) async {
      final subagents = [
        const SubagentItem(
          id: 'sub_code_reviewer',
          name: 'Code Reviewer',
          model: 'gemini-1.5-pro',
          cost: 0.0125,
          status: 'completed',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('sess_cost_test').overrideWith(
              (ref) => SessionStateNotifier('sess_cost_test', null)
                ..state = const SessionState(
                  sessionId: 'sess_cost_test',
                  sessionName: 'Cost Test Session',
                  cwd: 'C:/projects/app',
                  currentModel: 'claude-3-5-sonnet',
                  sessionStats: {
                    'cost': 0.0200, // Agent cost = $0.0200
                  },
                ),
            ),
            subagentsFamily('sess_cost_test').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'sess_cost_test', subagents), // Subagent cost = $0.0125
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: TranscriptView(
                sessionId: 'sess_cost_test',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Total session cost should be 0.0200 + 0.0125 = $0.0325
      expect(find.textContaining('\$0.0325'), findsOneWidget);

      // Tap on Cost metric chip to open Level 0 breakdown popup
      await tester.tap(find.textContaining('\$0.0325'));
      await tester.pumpAndSettle();

      expect(find.text('Dettaglio Costi Sessione'), findsOneWidget);
      expect(find.byKey(const ValueKey('cost-breakdown-agent-row')), findsOneWidget);
      expect(find.byKey(const ValueKey('cost-breakdown-subagents-row')), findsOneWidget);

      // Click on Agent cost row -> navigate to Level 1
      await tester.tap(find.byKey(const ValueKey('cost-breakdown-agent-row')));
      await tester.pumpAndSettle();

      expect(find.text('Costi Modelli Agente'), findsOneWidget);
      expect(find.text('claude-3-5-sonnet'), findsWidgets);
      expect(find.text('\$0.0200'), findsWidgets);

      // Click Back button to return to Level 0
      await tester.tap(find.byKey(const ValueKey('cost-breakdown-back-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Dettaglio Costi Sessione'), findsOneWidget);

      // Click on Subagents cost row -> navigate to Level 2
      await tester.tap(find.byKey(const ValueKey('cost-breakdown-subagents-row')));
      await tester.pumpAndSettle();

      expect(find.text('Costi Subagenti & Modelli'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Code Reviewer'),
        ),
        findsOneWidget,
      );
      expect(find.text('gemini-1.5-pro'), findsWidgets);
      expect(find.text('\$0.0125'), findsWidgets);

      // Click close button
      await tester.tap(find.byKey(const ValueKey('cost-breakdown-close-btn')));
      await tester.pumpAndSettle();

      // Dialog is dismissed
      expect(find.text('Costi Subagenti & Modelli'), findsNothing);
    });

    testWidgets('Chat parses <task-notification> and displays formatted card instead of raw XML', (tester) async {
      const rawTaskNotification = '''
<task-notification>
<task-id>05928f01-b805-46c</task-id>
<tool-use-id>call_12345</tool-use-id>
<output-file>C:\\Temp\\tasks\\05928f01-b805-46c.output</output-file>
<status>Wrapped up (turn limit)</status>
<summary>Agent "Probe CM5 offscreen GL safely" steered</summary>
<result>Phase 2 EGL/GLES smoke passed. 1440x1200 source fits texture limit.</result>
<usage><total_tokens>30467</total_tokens><tool_uses>21</tool_uses><context_percent>3</context_percent><duration_ms>178345</duration_ms></usage>
</task-notification>
Full transcript available at: C:\\Temp\\tasks\\05928f01-b805-46c.output
''';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('sess_notif_test').overrideWith(
              (ref) => SessionStateNotifier('sess_notif_test', null)
                ..state = const SessionState(
                  sessionId: 'sess_notif_test',
                  sessionName: 'Notification Test',
                  cwd: 'C:/projects/app',
                  entries: [
                    SessionEntry(
                      id: 'msg-notif-1',
                      role: 'assistant',
                      text: rawTaskNotification,
                      timestamp: 1000,
                    ),
                  ],
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: TranscriptView(
                sessionId: 'sess_notif_test',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Raw tags should NOT be displayed as plain text
      expect(find.textContaining('<task-notification>'), findsNothing);
      expect(find.textContaining('</task-notification>'), findsNothing);
      expect(find.textContaining('<tool-use-id>'), findsNothing);

      // Beautiful card should be rendered with summary, status, tokens, and duration
      expect(find.text('Notifica Subagente'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('task-notification-card-05928f01-b805-46c')),
          matching: find.textContaining('Agent "Probe CM5 offscreen GL safely" steered'),
        ),
        findsOneWidget,
      );
      expect(find.text('WRAPPED UP (TURN LIMIT)'), findsOneWidget);
      expect(find.text('30.5k tok'), findsOneWidget);
      expect(find.text('2m 58s'), findsOneWidget);
      expect(find.text('21 tool uses'), findsOneWidget);

      // Expandable result toggle
      expect(find.byKey(const ValueKey('task-notif-expand-result-btn')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('task-notif-expand-result-btn')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('task-notification-card-05928f01-b805-46c')),
          matching: find.textContaining('Phase 2 EGL/GLES smoke passed.'),
        ),
        findsOneWidget,
      );
    });

    test('SubagentsNotifier updates in real time when activeToolCalls are added to SessionState', () {
      final sessionNotifier = SessionStateNotifier('realtime_subagent_test', null)
        ..state = const SessionState(
          sessionId: 'realtime_subagent_test',
          cwd: 'C:/test',
        );

      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('realtime_subagent_test').overrideWith(
            (ref) => sessionNotifier,
          ),
        ],
      );
      addTearDown(container.dispose);

      final subagentsNotifier = container.read(subagentsFamily('realtime_subagent_test').notifier);
      expect(subagentsNotifier.state, isEmpty);

      // Simulate a subagent tool being launched in real time
      sessionNotifier.state = sessionNotifier.state.copyWith(
        activeToolCalls: {
          'tool-subagent-1': const ToolExecutionState(
            toolCallId: 'tool-subagent-1',
            toolName: 'delegate',
            args: {
              'description': 'Run native core tests',
              'subagent_type': 'reviewer',
              'model': 'gpt-6-luna',
            },
            isRunning: true,
          ),
        },
      );

      // SubagentsNotifier must reactively pick up the running subagent in real-time
      expect(subagentsNotifier.state.length, 1);
      final sub = subagentsNotifier.state.first;
      expect(sub.id, 'tool-subagent-1');
      expect(sub.name, 'reviewer');
      expect(sub.description, 'Run native core tests');
      expect(sub.model, 'gpt-6-luna');
      expect(sub.isRunning, isTrue);

      // Complete the tool call
      sessionNotifier.state = sessionNotifier.state.copyWith(
        activeToolCalls: {},
        entries: [
          const SessionEntry(
            id: 'entry-sub-complete',
            role: 'assistant',
            text: 'Subagent completed successfully. Cost: \$0.0150',
            timestamp: 2000,
            toolCalls: [
              ToolExecutionState(
                toolCallId: 'tool-subagent-1',
                toolName: 'delegate',
                args: {
                  'description': 'Run native core tests',
                  'subagent_type': 'reviewer',
                  'model': 'gpt-6-luna',
                },
                output: 'All tests passed',
                isRunning: false,
              ),
            ],
          ),
        ],
      );

      expect(subagentsNotifier.state.length, 1);
      final completedSub = subagentsNotifier.state.first;
      expect(completedSub.isCompleted, isTrue);
      expect(completedSub.output, 'All tests passed');
      expect(completedSub.cost, 0.0150);
    });

    testWidgets('SubagentPopDown and subagents-book-tab render cost badge correctly', (tester) async {
      final subagents = [
        const SubagentItem(
          id: 'sub-1',
          name: 'Worker Alpha',
          model: 'claude-3-5-sonnet',
          cost: 0.025,
          status: 'completed',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subagentsFamily('test_cost_sub').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'test_cost_sub', subagents),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: SubagentsPopDown(sessionId: 'test_cost_sub'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header cost badge and item row
      expect(find.text('\$0.0250'), findsNWidgets(2));
    });
  });
}
