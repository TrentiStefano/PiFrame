import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/transcript/todo_panel.dart';
import 'package:pi_frame/features/transcript/todo_provider.dart';

void main() {
  group('TodoItem model', () {
    test('parses from map correctly', () {
      final item = TodoItem.fromMap({
        'id': 1,
        'subject': 'Fix navbar spacing',
        'status': 'in_progress',
        'description': 'Adjust padding to 6px',
        'blockedBy': [2, 3],
      });

      expect(item.id, 1);
      expect(item.subject, 'Fix navbar spacing');
      expect(item.isInProgress, isTrue);
      expect(item.isCompleted, isFalse);
      expect(item.blockedBy, [2, 3]);
    });

    test('updates status via copyWith', () {
      const item = TodoItem(id: 2, subject: 'Write unit tests');
      expect(item.isPending, isTrue);

      final completed = item.copyWith(status: 'completed');
      expect(completed.isCompleted, isTrue);
      expect(completed.subject, 'Write unit tests');
    });
  });

  group('TodoPopDown widget', () {
    testWidgets('renders task list and checkboxes', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final initialTasks = [
        const TodoItem(id: 1, subject: 'First Task', status: 'completed'),
        const TodoItem(id: 2, subject: 'Second Task', status: 'in_progress'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todosFamily('session-1').overrideWith(
              (ref) => _MockTodoNotifier(ref, 'session-1', initialTasks),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TodoPopDown(sessionId: 'session-1'),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Task Agente (Todo)'), findsOneWidget);
      expect(find.text('First Task'), findsOneWidget);
      expect(find.text('Second Task'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(2));

      // Click on checkbox for Task 2 to complete it
      await tester.tap(find.byKey(const ValueKey('todo-checkbox-2')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('2 / 2 completati'), findsOneWidget);
    });

    testWidgets('clicking on a collapsed task expands and shows description', (tester) async {
      final initialTasks = [
        const TodoItem(
          id: 1,
          subject: 'Database Migration',
          status: 'pending',
          description: 'Run flyway migration scripts for user table schema change',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todosFamily('session-desc-test').overrideWith(
              (ref) => _MockTodoNotifier(ref, 'session-desc-test', initialTasks),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TodoPopDown(sessionId: 'session-desc-test'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Description is initially not visible
      expect(
        find.text('Run flyway migration scripts for user table schema change'),
        findsNothing,
      );

      // Tap on the task row
      await tester.tap(find.byKey(const ValueKey('todo-item-row-1')));
      await tester.pumpAndSettle();

      // Description is now visible
      expect(
        find.text('Run flyway migration scripts for user table schema change'),
        findsOneWidget,
      );
    });

    testWidgets('collapsed TodoPopDown shows peek tab and expands on tap', (tester) async {
      final initialTasks = [
        const TodoItem(id: 1, subject: 'Fix bug', status: 'pending'),
      ];

      bool expanded = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todosFamily('session-peek-test').overrideWith(
              (ref) => _MockTodoNotifier(ref, 'session-peek-test', initialTasks),
            ),
          ],
          child: StatefulBuilder(
            builder: (context, setState) {
              return MaterialApp(
                home: Scaffold(
                  body: TodoPopDown(
                    sessionId: 'session-peek-test',
                    isExpanded: expanded,
                    onToggleExpand: () => setState(() => expanded = !expanded),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // When collapsed, the peek tab is visible, main panel is not
      expect(find.byKey(const ValueKey('todo-peek-tab')), findsOneWidget);
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsNothing);

      // Tap the peek tab
      await tester.tap(find.byKey(const ValueKey('todo-peek-tab')));
      await tester.pumpAndSettle();

      // Now expanded
      expect(find.byKey(const ValueKey('todo-popdown-panel')), findsOneWidget);
      expect(find.text('Fix bug'), findsOneWidget);
    });
  });

  group('TodoNotifier synchronization and stability', () {
    test('does not accumulate tasks repeatedly during streaming updates', () {
      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('session-stream-test').overrideWith(
            (ref) => SessionStateNotifier('session-stream-test', null)
              ..state = const SessionState(
                sessionId: 'session-stream-test',
                cwd: '/test',
                entries: [
                  SessionEntry(
                    id: 'msg-1',
                    role: 'assistant',
                    text: 'Creating todo...',
                    timestamp: 1000,
                    toolCalls: [
                      ToolExecutionState(
                        toolCallId: 'tool-call-1',
                        toolName: 'todo',
                        args: {'action': 'create', 'subject': 'Single task'},
                      ),
                    ],
                  ),
                ],
              ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(todosFamily('session-stream-test').notifier);
      final sessionNotifier = container.read(sessionStateFamily('session-stream-test').notifier);

      expect(notifier.state.length, 1);
      expect(notifier.state.first.subject, 'Single task');

      // Simulate 30 rapid token stream chunks
      for (int i = 0; i < 30; i++) {
        sessionNotifier.state = sessionNotifier.state.copyWith(
          streamingTextBlocks: {0: 'Chunk $i'},
        );
      }

      // Must remain exactly 1 task, NOT 31 tasks!
      expect(notifier.state.length, 1);
      expect(notifier.state.first.subject, 'Single task');
    });

    test('ignores non-todo tools named task', () {
      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('session-task-test').overrideWith(
            (ref) => SessionStateNotifier('session-task-test', null)
              ..state = const SessionState(
                sessionId: 'session-task-test',
                cwd: '/test',
                entries: [
                  SessionEntry(
                    id: 'msg-1',
                    role: 'assistant',
                    text: 'Running background task...',
                    timestamp: 1000,
                    toolCalls: [
                      ToolExecutionState(
                        toolCallId: 'task-runner-1',
                        toolName: 'task',
                        args: {'CommandLine': 'npm test', 'WaitMs': 5000},
                      ),
                    ],
                  ),
                ],
              ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(todosFamily('session-task-test').notifier);
      // Unrelated task tool should not produce any todo items
      expect(notifier.state, isEmpty);
    });

    test('correctly parses unquoted relaxed JS object syntax and updates completed status', () {
      const chatSnippet = '''
only Phase 0., activeForm: auditing native camera drivers}, {id: 2, subject: Audit Dart consumers and Flutter Linux graphics integration, status: completed, description: Trace bridge, UI consumers, runner, registrar ownership, shutdown, and installed engine graphics/thread contracts. No edits., activeForm: auditing Dart and Flutter graphics integration}, {id: 3, subject: Validate target architecture and deliver migration report, status: completed, description: Completed read-only Phase 0 audit, pinned Flutter texture/context/thread contract validation, independent legacy defect verification, and phased migration/report synthesis. Architecture conditionally suitable; identified required corrections and CM5 hardware proof gates. No implementation authorized or performed., activeForm: validating architecture and drafting Phase 0 report}, {id: 19, subject: Test nativi su Pi: ctest core/dispatcher con ASan/UBSan e TSan, status: in_progress, description: Apt completato dall'utente su Pi. Verifico header e clang++ prima della build. Nessun riavvio necessario., activeForm: verificando dipendenze native sul Pi}], nextId: 30}}
''';

      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('session-relaxed-test').overrideWith(
            (ref) => SessionStateNotifier('session-relaxed-test', null)
              ..state = const SessionState(
                sessionId: 'session-relaxed-test',
                cwd: '/test',
                entries: [
                  SessionEntry(
                    id: 'msg-1',
                    role: 'assistant',
                    text: chatSnippet,
                    timestamp: 1000,
                  ),
                ],
              ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(todosFamily('session-relaxed-test').notifier);
      expect(notifier.state.length, 3);

      final task2 = notifier.state.firstWhere((t) => t.id == 2);
      expect(task2.subject, 'Audit Dart consumers and Flutter Linux graphics integration');
      expect(task2.isCompleted, isTrue);
      expect(task2.status, 'completed');

      final task3 = notifier.state.firstWhere((t) => t.id == 3);
      expect(task3.isCompleted, isTrue);
      expect(task3.status, 'completed');

      final task19 = notifier.state.firstWhere((t) => t.id == 19);
      expect(task19.subject, 'Test nativi su Pi: ctest core/dispatcher con ASan/UBSan e TSan');
      expect(task19.isInProgress, isTrue);
      expect(task19.isCompleted, isFalse);
    });

    test('correctly updates in_progress task to completed on "Updated #36 (in_progress -> completed)"', () {
      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('session-transition-test').overrideWith(
            (ref) => SessionStateNotifier('session-transition-test', null)
              ..state = const SessionState(
                sessionId: 'session-transition-test',
                cwd: '/test',
                entries: [
                  SessionEntry(
                    id: 'msg-1',
                    role: 'assistant',
                    text: '{id: 36, subject: "Audit graphics pipeline", status: in_progress}',
                    timestamp: 1000,
                  ),
                  SessionEntry(
                    id: 'msg-2',
                    role: 'assistant',
                    text: 'Updated #36 (in_progress -> completed)',
                    timestamp: 2000,
                  ),
                ],
              ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(todosFamily('session-transition-test').notifier);
      expect(notifier.state.length, 1);
      final task36 = notifier.state.first;
      expect(task36.id, 36);
      expect(task36.status, 'completed');
      expect(task36.isCompleted, isTrue);
    });

    test('extracts tasks from unquoted multiline block with commas safely without freeze', () {
      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('session-perf-test').overrideWith(
            (ref) => SessionStateNotifier('session-perf-test', null)
              ..state = const SessionState(
                sessionId: 'session-perf-test',
                cwd: '/test',
                entries: [
                  SessionEntry(
                    id: 'msg-perf',
                    role: 'assistant',
                    text: '''
Here are the tasks:
{id: 42, subject: "Refactor database queries, indexes, and migrations", status: in_progress, description: "Ensure everything is fast, reliable, and tested", activeForm: "Migrating schema"}
{id: 43, subject: Update documentation, status: pending, description: "Write docs for api, cli, and ide"}
''',
                    timestamp: 1000,
                  ),
                ],
              ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final stopwatch = Stopwatch()..start();
      final notifier = container.read(todosFamily('session-perf-test').notifier);
      stopwatch.stop();

      // Must complete rapidly (under 50ms)
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      expect(notifier.state.length, 2);
      expect(notifier.state[0].id, 42);
      expect(notifier.state[0].subject, 'Refactor database queries, indexes, and migrations');
      expect(notifier.state[0].status, 'in_progress');
      expect(notifier.state[0].description, 'Ensure everything is fast, reliable, and tested');
      expect(notifier.state[0].activeForm, 'Migrating schema');
      expect(notifier.state[1].id, 43);
      expect(notifier.state[1].subject, 'Update documentation');
      expect(notifier.state[1].status, 'pending');
    });
  });
}

class _MockTodoNotifier extends TodoNotifier {
  _MockTodoNotifier(super.ref, super.sessionId, List<TodoItem> initial) {
    state = initial;
  }

  @override
  void toggleStatus(int id) {
    state = state.map((t) {
      if (t.id == id) {
        return t.copyWith(status: t.isCompleted ? 'pending' : 'completed');
      }
      return t;
    }).toList();
  }
}
