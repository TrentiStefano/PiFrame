import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame/ui/code/code_editor_controller.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class MockWorkspaceSearchClient extends PcpClient {
  MockWorkspaceSearchClient() : super(port: 1, token: 'test');

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async {
    return {
      'data': {
        'rootPath': '/projects/test',
        'files': [
          {'path': 'main.dart', 'type': 'file', 'size': 120},
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> readWorkspaceFile(String sessionId, String path) async {
    return {
      'data': {
        'content': 'void main() {\n  final message = "Hello PiFrame";\n  print(message);\n}',
        'revision': 'rev1',
        'rootPath': '/projects/test',
      },
    };
  }
}

void main() {
  test('CodeEditorController finds and highlights syntax and search matches', () {
    final tokens = FrameTokens.dark;
    final controller = CodeEditorController(
      text: 'const greeting = "Hello World";\nfinal second = "Hello Pi";',
      filePath: 'test.dart',
      tokens: tokens,
    );

    // Initial without search
    controller.searchQuery = '';
    final span1 = controller.buildTextSpan(
      context: DummyBuildContext(),
      withComposing: false,
    );
    expect(span1.children, isNotEmpty);

    // With search query "Hello"
    controller.searchQuery = 'Hello';
    final matches = controller.findMatches();
    expect(matches.length, 2);
    expect(matches[0].start, 18);
    expect(matches[1].start, 48);

    controller.currentMatchIndex = 0;
    final spanWithSearch = controller.buildTextSpan(
      context: DummyBuildContext(),
      withComposing: false,
    );
    expect(spanWithSearch.children, isNotEmpty);
  });

  testWidgets('RepositoryPane opens search bar and navigates matches', (tester) async {
    final client = MockWorkspaceSearchClient();
    final notifier = SessionStateNotifier('sess_search', client)
      ..state = SessionState(
        sessionId: 'sess_search',
        cwd: '/projects/test',
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          pcpClientProvider.overrideWithValue(client),
          sessionStateFamily('sess_search').overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: RepositoryPane(sessionId: 'sess_search')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select main.dart to open editor
    expect(find.text('main.dart'), findsOneWidget);
    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();

    // Verify search button in header
    final searchBtn = find.byKey(const ValueKey('repository-editor-search-btn'));
    expect(searchBtn, findsOneWidget);

    // Click search button to open floating search bar
    await tester.tap(searchBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('repository-file-search-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('repository-file-search-field')), findsOneWidget);

    // Enter query "message"
    await tester.enterText(
      find.byKey(const ValueKey('repository-file-search-field')),
      'message',
    );
    await tester.pumpAndSettle();

    // "message" appears twice in readWorkspaceFile content
    expect(find.text('1 di 2'), findsOneWidget);

    // Tap next match
    await tester.tap(find.byKey(const ValueKey('repository-file-search-next')));
    await tester.pumpAndSettle();
    expect(find.text('2 di 2'), findsOneWidget);

    // Tap prev match
    await tester.tap(find.byKey(const ValueKey('repository-file-search-prev')));
    await tester.pumpAndSettle();
    expect(find.text('1 di 2'), findsOneWidget);

    // Close search
    await tester.tap(find.byKey(const ValueKey('repository-file-search-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repository-file-search-bar')), findsNothing);
  });
}

class DummyBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
