import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/features/transcript/todo_panel.dart';
import 'package:pi_crust/features/transcript/todo_provider.dart';

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
