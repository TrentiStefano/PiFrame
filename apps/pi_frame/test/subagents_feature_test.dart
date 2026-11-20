import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/removed_repos_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_frame/features/side/side_provider.dart';
import 'package:pi_frame/features/transcript/subagent_panel.dart';
import 'package:pi_frame/features/transcript/subagents_provider.dart';
import 'package:pi_frame/features/transcript/todo_provider.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _TestPinnedNotifier extends PinnedSessionsNotifier {
  _TestPinnedNotifier(super.initial);
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

class _MountCounter extends StatefulWidget {
  final VoidCallback onMount;
  const _MountCounter({required this.onMount});

  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _MockTodoNotifier extends TodoNotifier {
  _MockTodoNotifier(super.ref, super.sessionId, List<TodoItem> initial) {
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

      // Folder 'app' exists and, holding the active session, is expanded by default.
      expect(find.text('app'), findsOneWidget);

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
              body: AgentActivityPanel(
                sessionId: 'test_session',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header and subagent details
      expect(find.text('Sessione principale'), findsOneWidget);
      expect(find.text('Explore Agent'), findsOneWidget);
      expect(find.textContaining('gpt-6-luna'), findsOneWidget);
      expect(find.textContaining('\$0.0175'), findsNWidgets(2));
      expect(find.textContaining('In corso'), findsWidgets);

      // Individual subagent cards start collapsed; expand to inspect output.
      expect(find.textContaining('Found 4 files matching auth query:'), findsNothing);
      await tester.tap(find.text('Explore Agent'));
      await tester.pumpAndSettle();
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
              body: AgentActivityPanel(
                sessionId: 'test_session',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Steering box should not be visible initially
      expect(find.byKey(const ValueKey('subagent-steer-box-sub_agent_steerable')), findsNothing);

      // Expand the card before opening its inline steering box.
      await tester.tap(find.text('Test Delegate'));
      await tester.pumpAndSettle();

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

      // Subagents header chip should NOT be in the session info card (removed per request)
      expect(find.byKey(const ValueKey('subagents-header-chip')), findsNothing);
      // Subagents moved to the side panel next to the chat card.
      expect(find.byKey(const ValueKey('subagents-book-tab')), findsNothing);
      expect(find.text('Active Subagent'), findsNothing);
    });

    testWidgets('agent activity sidecar opens from its strip and closes back to it', (tester) async {
      const subagents = [
        SubagentItem(
          id: 'sub_side',
          name: 'Side Agent',
          model: 'haiku',
          output: 'Side output',
          status: 'completed',
        ),
      ];
      var opened = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('sess_side').overrideWith(
              (ref) => SessionStateNotifier('sess_side', null)
                ..state = const SessionState(sessionId: 'sess_side', cwd: '/repo'),
            ),
            subagentsFamily('sess_side').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'sess_side', subagents),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(child: SizedBox()),
                  AgentActivitySidecar(sessionId: 'sess_side', onOpened: () => opened++),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('agent-activity-panel')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('agent-activity-open-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-activity-panel')), findsOneWidget);
      expect(find.text('Side Agent'), findsOneWidget);
      expect(opened, 1, reason: 'the shell collapses Git when the panel opens');

      await tester.tap(find.byKey(const ValueKey('sidecar-hide-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-activity-panel')), findsNothing);
      expect(find.byKey(const ValueKey('agent-activity-open-btn')), findsOneWidget);
    });

    testWidgets('closing the agents panel while an agent runs keeps it closed and Git stays open', (tester) async {
      const subagents = [
        SubagentItem(id: 'sub_run', name: 'Busy Agent', status: 'running'),
      ];
      var opened = 0;
      var chatMounts = 0;
      Widget app(double width) => ProviderScope(
            overrides: [
              sessionStateFamily('sess_run').overrideWith(
                (ref) => SessionStateNotifier('sess_run', null)
                  ..state = const SessionState(sessionId: 'sess_run', cwd: '/repo'),
              ),
              subagentsFamily('sess_run').overrideWith(
                (ref) => _MockSubagentsNotifier(ref, 'sess_run', subagents),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    height: 700,
                    child: AgentSidecarLayout(
                      sessionId: 'sess_run',
                      chat: _MountCounter(onMount: () => chatMounts++),
                      sidecar: AgentActivitySidecar(
                        key: const ValueKey('agent_activity_sess_run'),
                        sessionId: 'sess_run',
                        onOpened: () => opened++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

      // Narrow enough that the open panel floats over the chat.
      await tester.pumpWidget(app(600));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-activity-panel')), findsOneWidget,
          reason: 'a running agent opens the panel once');
      expect(opened, 1);

      await tester.tap(find.byKey(const ValueKey('sidecar-hide-btn')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('agent-activity-panel')), findsNothing,
          reason: 'closing must not bounce back open while the agent still runs');
      expect(find.byKey(const ValueKey('agent-activity-open-btn')), findsOneWidget);
      expect(opened, 1, reason: 'the shell must not collapse Git again');
      expect(chatMounts, 1, reason: 'switching between overlay and column keeps the chat mounted');

      // Reopen at a width where the panel sits beside the chat, then narrow it.
      await tester.pumpWidget(app(1200));
      await tester.tap(find.byKey(const ValueKey('agent-activity-open-btn')));
      await tester.pumpAndSettle();
      expect(opened, 2);
      await tester.pumpWidget(app(600));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-activity-panel')), findsOneWidget);
      expect(opened, 2, reason: 'a narrower chat (Git expanded) must not collapse Git again');
      expect(chatMounts, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('agents list running first, then settled, each newest launch first', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subagentsFamily('sess_order').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'sess_order', const [
                SubagentItem(id: 'old_run', name: 'old-running', status: 'running', startedAt: 100),
                SubagentItem(id: 'old_done', name: 'old-done', status: 'completed', startedAt: 200),
                SubagentItem(id: 'new_done', name: 'new-done', status: 'completed', startedAt: 900),
                SubagentItem(id: 'new_run', name: 'new-running', status: 'running', startedAt: 800),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(body: AgentActivityPanel(sessionId: 'sess_order')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-tree-completed-toggle')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('agent-tree-completed-toggle')));
      await tester.pumpAndSettle();
      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(y('new-running'), lessThan(y('old-running')));
      expect(y('old-running'), lessThan(y('new-done')));
      expect(y('new-done'), lessThan(y('old-done')));
    });

    testWidgets('agent rows built while scrolling do not jitter horizontally', (tester) async {
      tester.view.physicalSize = const Size(800, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subagentsFamily('sess_scroll').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'sess_scroll', [
                for (var i = 0; i < 40; i++)
                  SubagentItem(id: 'a$i', name: 'agent-$i', status: 'completed'),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(body: AgentActivityPanel(sessionId: 'sess_scroll')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final titles = find.textContaining(RegExp(r'^agent-\d+$'));
      final restingDx = tester.getTopLeft(titles.first).dx;

      await tester.drag(find.byKey(const ValueKey('agent-activity-panel')), const Offset(0, -700));
      // Mid-frame: lazily built rows used to still be sliding in from the right.
      await tester.pump(const Duration(milliseconds: 60));
      expect(titles, findsWidgets);
      for (final title in titles.evaluate()) {
        expect(tester.getTopLeft(find.byWidget(title.widget)).dx, restingDx);
      }
    });

    testWidgets('agent panel lists a workflow run and expands to its phases', (tester) async {
      const script = "export const meta = { name: 'audit', description: 'Audit the repo', "
          "phases: [{ title: 'Scan' }] }";
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('sess_wf').overrideWith(
              (ref) => SessionStateNotifier('sess_wf', null)
                ..state = const SessionState(
                  sessionId: 'sess_wf',
                  cwd: '/repo',
                  entries: [
                    SessionEntry(
                      id: 'a',
                      role: 'assistant',
                      text: '',
                      timestamp: 1,
                      toolCalls: [
                        ToolExecutionState(
                          toolCallId: 'call_wf',
                          toolName: 'SubagentWorkflow',
                          args: {'script': script},
                          output: 'Workflow "audit" started in the background.\nTask ID: wf_000000aaaaaa\n',
                        ),
                      ],
                    ),
                  ],
                ),
            ),
            subagentsFamily('sess_wf').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'sess_wf', const [
                SubagentItem(
                  id: 'child_1',
                  name: 'general-purpose#child_1',
                  status: 'running',
                  isUnlinked: true,
                  prompt: 'COMPITO: QA finale del sito',
                  activity: 'bash: npm test',
                  startedAt: 5,
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(body: AgentActivityPanel(sessionId: 'sess_wf')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('WORKFLOW'), findsOneWidget);
      expect(find.text('audit'), findsOneWidget);
      expect(find.text('In corso'), findsNWidgets(2));
      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('0/1 agenti finiti · 1 al lavoro'), findsOneWidget);
      // The workflow child shows its own task and what it is running now.
      expect(find.text('COMPITO: QA finale del sito'), findsOneWidget);
      expect(find.textContaining('npm test'), findsOneWidget);
      expect(find.text('Audit the repo'), findsNothing);
      expect(find.textContaining('wf_000000aaaaaa'), findsNothing);

      await tester.tap(find.text('audit'));
      await tester.pumpAndSettle();
      expect(find.text('Audit the repo'), findsOneWidget);
    });

    testWidgets('tasks live in a Tasks tab of the side panel, not over the chat', (tester) async {
      final subagents = [
        const SubagentItem(
          id: 'sub_agent_exclusive',
          name: 'Worker Agent',
          model: 'sonnet',
          cost: 0.005,
          output: 'Doing work...',
          status: 'running',
        ),
      ];
      final todos = [
        const TodoItem(
          id: 1,
          subject: 'Review database queries',
          status: 'pending',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('sess_tabs_1').overrideWith(
              (ref) => SessionStateNotifier('sess_tabs_1', null)
                ..state = const SessionState(
                  sessionId: 'sess_tabs_1',
                  sessionName: 'Tabs Test',
                  cwd: 'C:/projects/app',
                  agentStatus: AgentStatus.settled,
                ),
            ),
            subagentsFamily('sess_tabs_1').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'sess_tabs_1', subagents),
            ),
            todosFamily('sess_tabs_1').overrideWith(
              (ref) => _MockTodoNotifier(ref, 'sess_tabs_1', todos),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 1200,
                height: 700,
                child: AgentSidecarLayout(
                  sessionId: 'sess_tabs_1',
                  chat: TranscriptView(sessionId: 'sess_tabs_1'),
                  sidecar: AgentActivitySidecar(sessionId: 'sess_tabs_1'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The chat no longer carries a tasks chip or popup.
      expect(find.byKey(const ValueKey('todo-peek-tab')), findsNothing);
      // The running agent opened the panel; both kinds have a tab.
      expect(find.byKey(const ValueKey('agent-activity-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidecar-tab-agents')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidecar-tab-tasks')), findsOneWidget);
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('sidecar-tab-tasks')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsOneWidget);
      expect(find.text('Review database queries'), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-activity-panel')), findsNothing);

      // One hide button for the whole pane; the tabs have none of their own.
      expect(find.byKey(const ValueKey('todo-popdown-close-btn')), findsNothing);
      expect(find.byKey(const ValueKey('agent-activity-close-btn')), findsNothing);
      expect(find.byKey(const ValueKey('sidecar-hide-btn')), findsOneWidget);
      // The draggable border between chat and pane shows its line.
      expect(find.byKey(const ValueKey('sidecar-resize-handle')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sidecar-hide-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('agent-activity-panel')), findsNothing);
      expect(find.byKey(const ValueKey('agent-activity-open-btn')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('hiding the plugins pane keeps an unsent side draft', (tester) async {
      final container = ProviderContainer(overrides: [
        sessionStateFamily('sess_draft').overrideWith(
          (ref) => SessionStateNotifier('sess_draft', null)
            ..state = const SessionState(sessionId: 'sess_draft', cwd: 'C:/projects/app'),
        ),
        subagentsFamily('sess_draft').overrideWith(
          (ref) => _MockSubagentsNotifier(ref, 'sess_draft', const []),
        ),
      ]);
      addTearDown(container.dispose);
      container.read(sideThreadFamily('sess_draft').notifier).state = const SideThreadState(
        parentSessionId: 'sess_draft',
        sideId: 'side_1',
        streamId: 'stream_1',
        status: 'active',
        isOpen: true,
      );
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(
            body: SizedBox(
              width: 1200,
              height: 700,
              child: AgentSidecarLayout(
                sessionId: 'sess_draft',
                chat: SizedBox.expand(),
                sidecar: AgentActivitySidecar(sessionId: 'sess_draft'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('side-close-btn')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('side-mini-composer-input')), 'half a question');
      await tester.tap(find.byKey(const ValueKey('sidecar-hide-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('side-mini-composer-input')), findsNothing);

      container.read(sideThreadFamily('sess_draft').notifier).openPanel();
      await tester.pumpAndSettle();
      expect(find.text('half a question'), findsOneWidget);
    });

    testWidgets('new tasks open the Tasks tab until the user closes it', (tester) async {
      late _MockTodoNotifier todoNotifier;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('sess_tasks_auto').overrideWith(
              (ref) => SessionStateNotifier('sess_tasks_auto', null)
                ..state = const SessionState(
                  sessionId: 'sess_tasks_auto',
                  cwd: 'C:/projects/app',
                  agentStatus: AgentStatus.settled,
                ),
            ),
            subagentsFamily('sess_tasks_auto').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'sess_tasks_auto', const []),
            ),
            todosFamily('sess_tasks_auto').overrideWith((ref) {
              todoNotifier = _MockTodoNotifier(ref, 'sess_tasks_auto', const []);
              return todoNotifier;
            }),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(
              body: SizedBox(
                width: 1200,
                height: 700,
                child: AgentSidecarLayout(
                  sessionId: 'sess_tasks_auto',
                  chat: SizedBox.expand(),
                  sidecar: AgentActivitySidecar(sessionId: 'sess_tasks_auto'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-activity-open-btn')), findsNothing);

      todoNotifier.state = [const TodoItem(id: 1, subject: 'Plan the change', status: 'pending')];
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsOneWidget,
          reason: 'tasks the agent adds open the tab');

      await tester.tap(find.byKey(const ValueKey('sidecar-hide-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('agent-activity-open-btn')), findsOneWidget,
          reason: 'the closed panel leaves its strip to reopen it');

      todoNotifier.state = [
        ...todoNotifier.state,
        const TodoItem(id: 2, subject: 'Write the tests', status: 'pending'),
      ];
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsNothing,
          reason: 'after the user closed it, new tasks do not reopen it');

      await tester.tap(find.byKey(const ValueKey('agent-activity-open-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Write the tests'), findsOneWidget);
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
              body: AgentActivityPanel(sessionId: 'test_session'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      if (find.byKey(const ValueKey('agent-tree-completed-toggle')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('agent-tree-completed-toggle')));
        await tester.pumpAndSettle();
      }

      // Ensure no Checkbox exists (user should not be able to checkmark subagent tasks)
      expect(find.byType(Checkbox), findsNothing);

      // Verify model used is displayed
      expect(find.textContaining('claude-3-5-sonnet'), findsOneWidget);

      // Find the text widget for completed agent task and verify strikethrough decoration
      final titleFinder = find.text('Completed Agent Task');
      expect(titleFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(titleFinder);
      expect(textWidget.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('Pi cost is not added to separately reported subagent cost', (tester) async {
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

      // Pi cost may already include subagent usage, so never add them blindly.
      expect(find.textContaining('\$0.0200'), findsOneWidget);
      expect(find.textContaining('\$0.0325'), findsNothing);

      // Tap on Cost metric chip to open Level 0 breakdown popup
      await tester.ensureVisible(find.textContaining('\$0.0200'));
      await tester.tap(find.textContaining('\$0.0200'));
      await tester.pumpAndSettle();

      expect(find.text('Dettaglio costi sessione'), findsOneWidget);
      expect(find.byKey(const ValueKey('cost-breakdown-agent-row')), findsOneWidget);
      expect(find.byKey(const ValueKey('cost-breakdown-subagents-row')), findsOneWidget);

      // Click on Agent cost row -> navigate to Level 1
      await tester.tap(find.byKey(const ValueKey('cost-breakdown-agent-row')));
      await tester.pumpAndSettle();

      expect(find.text('Costi modelli agente'), findsOneWidget);
      expect(find.text('Costi per modello non disponibili'), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-model-cost-claude-3-5-sonnet')), findsNothing);
      expect(find.text('\$0.0200'), findsWidgets);

      // Click Back button to return to Level 0
      await tester.tap(find.byKey(const ValueKey('cost-breakdown-back-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Dettaglio costi sessione'), findsOneWidget);

      // Click on Subagents cost row -> navigate to Level 2
      await tester.tap(find.byKey(const ValueKey('cost-breakdown-subagents-row')));
      await tester.pumpAndSettle();

      expect(find.text('Costi subagenti & modelli'), findsOneWidget);
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
      expect(find.text('Costi subagenti & modelli'), findsNothing);
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
      expect(find.text('Notifica subagente'), findsOneWidget);
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

    testWidgets('a code fence inside <result> does not break the notification into raw XML', (tester) async {
      const raw = '''
<task-notification>
<task-id>3c52f51e-5f5f-408</task-id>
<tool-use-id>call_UFQPNGXjbKGi/8CP254f+qQEosFC0Z3eQ==</tool-use-id>
<output-file>C:\\Temp\\tasks\\3c52f51e-5f5f-408.output</output-file>
<status>Wrapped up (turn limit)</status>
<summary>Agent "Hold debug app session" steered</summary>
<result>Startup failed. WSL reported:

```text
/mnt/c/flutter/bin/internal/shared.sh: line 5: \$'\\r': command not found
```

The app did not stay open.</result>
<usage><total_tokens>65262</total_tokens><tool_uses>2</tool_uses><context_percent>3</context_percent><duration_ms>32199</duration_ms></usage>
</task-notification>
Full transcript available at: C:\\Temp\\tasks\\3c52f51e-5f5f-408.output
''';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('sess_notif_fence').overrideWith(
              (ref) => SessionStateNotifier('sess_notif_fence', null)
                ..state = const SessionState(
                  sessionId: 'sess_notif_fence',
                  cwd: 'C:/projects/app',
                  entries: [
                    SessionEntry(
                      id: 'msg-notif-fence',
                      role: 'custom',
                      text: raw,
                      timestamp: 1000,
                      metadata: {'customType': 'subagent-notification'},
                    ),
                  ],
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(body: TranscriptView(sessionId: 'sess_notif_fence')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('<task-notification>'), findsNothing);
      expect(find.textContaining('<tool-use-id>'), findsNothing);
      expect(find.textContaining('</result>'), findsNothing);
      expect(find.byKey(const ValueKey('task-notification-card-3c52f51e-5f5f-408')), findsOneWidget);
    });

    test('SubagentsNotifier does not present an estimate as actual cost', () {
      const taskNotification = '''
<task-notification>
<task-id>agent_12345678</task-id>
<tool-use-id>call_estimated_agent</tool-use-id>
<status>Done</status>
<summary>Agent "reviewer" completed</summary>
<result>Review passed.</result>
<usage><total_tokens>1200</total_tokens><tool_uses>3</tool_uses><estimated_cost_usd>0.0150</estimated_cost_usd><duration_ms>12000</duration_ms></usage>
</task-notification>
''';
      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('estimated_cost_test').overrideWith(
            (ref) => SessionStateNotifier('estimated_cost_test', null)
              ..state = const SessionState(
                sessionId: 'estimated_cost_test',
                cwd: '/repo',
                entries: [
                  SessionEntry(
                    id: 'launch',
                    role: 'assistant',
                    text: '',
                    timestamp: 900,
                    toolCalls: [
                      ToolExecutionState(
                        toolCallId: 'call_estimated_agent',
                        toolName: 'Agent',
                        args: {'subagent_type': 'reviewer'},
                      ),
                    ],
                  ),
                  SessionEntry(
                    id: 'notification',
                    role: 'assistant',
                    text: taskNotification,
                    timestamp: 1000,
                  ),
                ],
              ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final subagents = container.read(subagentsFamily('estimated_cost_test'));
      expect(subagents, hasLength(1));
      expect(subagents.single.cost, isNull);
    });

    test('SubagentsNotifier merges task notification with its worker tool call', () {
      const taskNotification = '''
<task-notification>
<task-id>agent_task_1</task-id>
<tool-use-id>call_worker_1</tool-use-id>
<status>Done</status>
<summary>Agent "Remove folder-row glow" completed</summary>
<result>Session-browser indicator fix implemented.</result>
<usage><total_tokens>43294</total_tokens><tool_uses>17</tool_uses><context_percent>4</context_percent><duration_ms>70724</duration_ms></usage>
</task-notification>
''';
      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('worker_notification_merge').overrideWith(
            (ref) => SessionStateNotifier('worker_notification_merge', null)
              ..state = const SessionState(
                sessionId: 'worker_notification_merge',
                cwd: '/repo',
                entries: [
                  SessionEntry(
                    id: 'worker-tool-call',
                    role: 'assistant',
                    text: '',
                    timestamp: 1000,
                    toolCalls: [
                      ToolExecutionState(
                        toolCallId: 'call_worker_1',
                        toolName: 'worker',
                        args: {'subagent_type': 'worker'},
                        output: 'Worker completed: 43.3k tokens',
                      ),
                    ],
                  ),
                  SessionEntry(
                    id: 'worker-notification',
                    role: 'assistant',
                    text: taskNotification,
                    timestamp: 2000,
                  ),
                ],
              ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final subagents = container.read(
        subagentsFamily('worker_notification_merge'),
      );
      expect(subagents, hasLength(1));
      expect(subagents.single.id, 'agent_task_1');
      expect(subagents.single.name, 'Remove folder-row glow');
      expect(subagents.single.toolCallId, 'call_worker_1');
      expect(subagents.single.cost, isNull);
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
      expect(sub.model, isNull); // A requested model is not proof of the model used.
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
      // Arbitrary assistant prose is not authoritative subagent billing data.
      expect(completedSub.cost, isNull);
    });

    testWidgets('Missing subagent cost is shown as unavailable, not zero', (tester) async {
      final subagents = [
        const SubagentItem(
          id: 'unpriced-worker',
          name: 'Unpriced Worker',
          status: 'completed',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subagentsFamily('unknown_cost_sub').overrideWith(
              (ref) => _MockSubagentsNotifier(ref, 'unknown_cost_sub', subagents),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: AgentActivityPanel(sessionId: 'unknown_cost_sub'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('N/D · N/D'), findsOneWidget); // Unknown model and cost.
      expect(find.text('\$0.0000'), findsNothing);
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
              body: AgentActivityPanel(sessionId: 'test_cost_sub'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header cost badge and item row
      expect(find.textContaining('\$0.0250'), findsNWidgets(2));
    });

    testWidgets('Changing session keeps cards minimized and does not re-open expanded cards', (tester) async {
      final subagentsA = [
        const SubagentItem(
          id: 'sub_a',
          name: 'Worker A',
          status: 'running',
        ),
      ];
      final todosA = [
        const TodoItem(id: 1, subject: 'Task A', status: 'pending'),
      ];
      final subagentsB = [
        const SubagentItem(
          id: 'sub_b',
          name: 'Worker B',
          status: 'running',
        ),
      ];
      final todosB = [
        const TodoItem(id: 2, subject: 'Task B', status: 'pending'),
      ];

      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('sess_a').overrideWith(
            (ref) => SessionStateNotifier('sess_a', null)
              ..state = const SessionState(
                sessionId: 'sess_a',
                sessionName: 'Session A',
                cwd: 'C:/projects/app',
                agentStatus: AgentStatus.settled,
              ),
          ),
          sessionStateFamily('sess_b').overrideWith(
            (ref) => SessionStateNotifier('sess_b', null)
              ..state = const SessionState(
                sessionId: 'sess_b',
                sessionName: 'Session B',
                cwd: 'C:/projects/app',
                agentStatus: AgentStatus.settled,
              ),
          ),
          subagentsFamily('sess_a').overrideWith(
            (ref) => _MockSubagentsNotifier(ref, 'sess_a', subagentsA),
          ),
          todosFamily('sess_a').overrideWith(
            (ref) => _MockTodoNotifier(ref, 'sess_a', todosA),
          ),
          subagentsFamily('sess_b').overrideWith(
            (ref) => _MockSubagentsNotifier(ref, 'sess_b', subagentsB),
          ),
          todosFamily('sess_b').overrideWith(
            (ref) => _MockTodoNotifier(ref, 'sess_b', todosB),
          ),
        ],
      );

      final currentSessionNotifier = ValueNotifier<String>('sess_a');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: Scaffold(
              body: ValueListenableBuilder<String>(
                valueListenable: currentSessionNotifier,
                builder: (context, sid, _) => TranscriptView(sessionId: sid),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Session A starts with both cards minimized
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('subagents-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('todo-peek-tab')), findsNothing);
      expect(find.byKey(const ValueKey('subagents-book-tab')), findsNothing);


      // Switch to Session B
      currentSessionNotifier.value = 'sess_b';
      await tester.pumpAndSettle();

      // Session B must NOT reopen with expanded card; it must normally be minimized
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('subagents-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('todo-peek-tab')), findsNothing);
      expect(find.byKey(const ValueKey('subagents-book-tab')), findsNothing);

      // Switch back to Session A
      currentSessionNotifier.value = 'sess_a';
      await tester.pumpAndSettle();

      // Reopening Session A also opens with minimized cards
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('subagents-popdown-panel')), findsNothing);
    });

    testWidgets('Changing session keeps cards minimized and does not re-open expanded cards', (tester) async {
      final subagentsA = [
        const SubagentItem(id: 'sub_a', name: 'Worker A', status: 'running'),
      ];
      final todosA = [
        const TodoItem(id: 1, subject: 'Task A', status: 'pending'),
      ];
      final subagentsB = [
        const SubagentItem(id: 'sub_b', name: 'Worker B', status: 'running'),
      ];
      final todosB = [
        const TodoItem(id: 2, subject: 'Task B', status: 'pending'),
      ];

      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('sess_a').overrideWith(
            (ref) => SessionStateNotifier('sess_a', null)
              ..state = const SessionState(
                sessionId: 'sess_a',
                sessionName: 'Session A',
                cwd: 'C:/projects/app',
                agentStatus: AgentStatus.settled,
              ),
          ),
          sessionStateFamily('sess_b').overrideWith(
            (ref) => SessionStateNotifier('sess_b', null)
              ..state = const SessionState(
                sessionId: 'sess_b',
                sessionName: 'Session B',
                cwd: 'C:/projects/app',
                agentStatus: AgentStatus.settled,
              ),
          ),
          subagentsFamily('sess_a').overrideWith(
            (ref) => _MockSubagentsNotifier(ref, 'sess_a', subagentsA),
          ),
          todosFamily('sess_a').overrideWith(
            (ref) => _MockTodoNotifier(ref, 'sess_a', todosA),
          ),
          subagentsFamily('sess_b').overrideWith(
            (ref) => _MockSubagentsNotifier(ref, 'sess_b', subagentsB),
          ),
          todosFamily('sess_b').overrideWith(
            (ref) => _MockTodoNotifier(ref, 'sess_b', todosB),
          ),
        ],
      );
      final currentSessionNotifier = ValueNotifier<String>('sess_a');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: Scaffold(
              body: ValueListenableBuilder<String>(
                valueListenable: currentSessionNotifier,
                builder: (context, sid, _) => TranscriptView(sessionId: sid),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('subagents-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('todo-peek-tab')), findsNothing);
      expect(find.byKey(const ValueKey('subagents-book-tab')), findsNothing);


      currentSessionNotifier.value = 'sess_b';
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('subagents-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('todo-peek-tab')), findsNothing);
      expect(find.byKey(const ValueKey('subagents-book-tab')), findsNothing);

      currentSessionNotifier.value = 'sess_a';
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsNothing);
      expect(find.byKey(const ValueKey('subagents-popdown-panel')), findsNothing);

      currentSessionNotifier.dispose();
      container.dispose();
    });
  });
}
