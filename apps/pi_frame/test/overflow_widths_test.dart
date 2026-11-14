import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'package:pi_frame/features/browser/browser_controller.dart';
import 'package:pi_frame/features/browser/web_browser_pane.dart';
import 'package:pi_frame/features/transcript/todo_panel.dart';
import 'package:pi_frame/features/transcript/todo_provider.dart';

/// Narrow widths that every companion/transcript widget must survive without
/// a RenderFlex overflow (audit P1-4, R1, R2; plan task 1.2).
const List<double> kNarrowWidths = [280, 320];

class _EmptyHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(
        '<html><head><title>Empty</title></head><body></body></html>'
            .codeUnits,
      ),
      404,
    );
  }
}

Widget _themed({required Widget child, List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  _todoTests();
  group('Browser companion fits narrow widths (task 1.2a)', () {
    for (final width in kNarrowWidths) {
      testWidgets('toolbar and header do not overflow at ${width.toInt()} px',
          (tester) async {
        await tester.pumpWidget(
          _themed(
            overrides: [
              browserClientProvider.overrideWithValue(_EmptyHttpClient()),
            ],
            child: SizedBox(
              width: width,
              height: 700,
              child: WebBrowserPane(
                sessionId: 'test-session',
                onCollapse: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('browser-omnibox-input')),
          findsOneWidget,
        );
      });
    }

    testWidgets('narrow companion moves home and bookmark into the toolbar menu',
        (tester) async {
      await tester.pumpWidget(
        _themed(
          overrides: [
            browserClientProvider.overrideWithValue(_EmptyHttpClient()),
          ],
          child: const SizedBox(
            width: 280,
            height: 700,
            child: WebBrowserPane(sessionId: 'test-session'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('browser-home-btn')), findsNothing);
      expect(find.byKey(const ValueKey('browser-bookmark-btn')), findsNothing);
      expect(
        find.byKey(const ValueKey('browser-toolbar-overflow-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('browser-companion-overflow-btn')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide companion keeps home and bookmark in the toolbar',
        (tester) async {
      await tester.pumpWidget(
        _themed(
          overrides: [
            browserClientProvider.overrideWithValue(_EmptyHttpClient()),
          ],
          child: const SizedBox(
            width: 480,
            height: 700,
            child: WebBrowserPane(sessionId: 'test-session'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('browser-home-btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('browser-bookmark-btn')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('browser-toolbar-overflow-btn')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _FixedTodoNotifier extends TodoNotifier {
  _FixedTodoNotifier(super.ref, super.sessionId, List<TodoItem> initial) {
    state = initial;
  }
}

void _todoTests() {
  group('Todo panel fits narrow widths (task 1.2b)', () {
    for (final width in kNarrowWidths) {
      testWidgets('header and task rows do not overflow at ${width.toInt()} px',
          (tester) async {
        const sessionId = 'overflow-todo';
        final tasks = [
          const TodoItem(
            id: 1,
            subject: 'Refactor the transcript header and the assistant card layout',
            status: 'completed',
          ),
          const TodoItem(
            id: 2,
            subject: 'Write widget tests for the narrow sidecar layout',
            status: 'in_progress',
            description: 'A very long description that wraps across lines.',
          ),
          const TodoItem(id: 3, subject: 'Pending task'),
        ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              todosFamily(sessionId).overrideWith(
                (ref) => _FixedTodoNotifier(ref, sessionId, tasks),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
              home: Scaffold(
                body: SizedBox(
                  width: width,
                  child: const TodoPopDown(sessionId: sessionId),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
