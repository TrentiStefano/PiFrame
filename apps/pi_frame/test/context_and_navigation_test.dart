import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_frame/features/session_tree/session_tree_dialog.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

class _SessionCreateClient extends PcpClient {
  _SessionCreateClient() : super(port: 1, token: 'test');

  final commands = <PcpCommand>[];

  @override
  Future<Map<String, dynamic>> sendCommand(PcpCommand command) async {
    commands.add(command);
    return {
      'data': {
        'session': {'id': 'new-session'},
      },
    };
  }
}

void main() {
  Widget wrapWithThemeAndScope(
    Widget child, {
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        ...overrides,
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets(
    'SessionsSidebar displays search field, filter chips, and filters sessions',
    (tester) async {
      final mockSessions = [
        {
          'id': 'sess_1',
          'name': 'Feature Branch A',
          'cwd': '/projects/pi-frame',
          'isActive': true,
          'lastMessagePreview': 'Implementing git diff viewer',
        },
        {
          'id': 'sess_2',
          'name': 'Bugfix Session B',
          'cwd': '/projects/other-repo',
          'isActive': false,
          'lastMessagePreview': 'Fixing stream buffer overflow',
        },
      ];

      await tester.pumpWidget(
        wrapWithThemeAndScope(
          const SessionsSidebar(),
          overrides: [
            sessionListProvider.overrideWith(
              (ref) => Future.value(mockSessions),
            ),
            activeSessionIdProvider.overrideWith((ref) => 'sess_1'),
          ],
        ),
      );

      await tester.pumpAndSettle();

      // Verify header and search field
      expect(find.text('Sessioni'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Tutte'), findsOneWidget);
      expect(find.text('Gestite'), findsOneWidget);
      expect(find.text('Questo repo'), findsOneWidget);

      // Folders should initially be visible minimized
      expect(find.text('pi-frame'), findsOneWidget);
      expect(find.text('other-repo'), findsOneWidget);

      // Expand folders to view sessions
      await tester.tap(find.text('pi-frame'));
      await tester.tap(find.text('other-repo'));
      await tester.pumpAndSettle();

      expect(find.text('Feature Branch A'), findsOneWidget);
      expect(find.text('Bugfix Session B'), findsOneWidget);

      // Filter by search query (auto-expands matching folders)
      await tester.enterText(find.byType(TextField), 'diff viewer');
      await tester.pumpAndSettle();

      expect(find.text('Feature Branch A'), findsOneWidget);
      expect(find.text('Bugfix Session B'), findsNothing);

      // Clear search
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      // Filter by daemon-managed sessions.
      await tester.tap(find.text('Gestite'));
      await tester.pumpAndSettle();

      expect(find.text('Feature Branch A'), findsOneWidget);
      expect(find.text('Bugfix Session B'), findsNothing);
    },
  );

  testWidgets('session list groups by repo and hides worker sessions', (
    tester,
  ) async {
    final sessions = [
      {
        'id': 'a',
        'name': 'First',
        'cwd': '/repo/packages/a',
        'gitRoot': '/repo',
        'isActive': false,
      },
      {
        'id': 'b',
        'name': 'Second',
        'cwd': '/repo/packages/b',
        'gitRoot': '/repo',
        'isActive': false,
      },
      {
        'id': 'worker#19',
        'name': 'worker#19',
        'cwd': '/repo',
        'gitRoot': '/repo',
        'isActive': false,
      },
      {
        'id': 'c',
        'name': 'Other',
        'cwd': '/other',
        'gitRoot': '/other',
        'isActive': false,
      },
    ];
    await tester.pumpWidget(
      wrapWithThemeAndScope(
        const SessionsSidebar(),
        overrides: [
          sessionListProvider.overrideWith((ref) => Future.value(sessions)),
          activeSessionIdProvider.overrideWith((ref) => 'a'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('session-folder:/repo')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-folder:/other')), findsOneWidget);
    expect(find.text('worker#19'), findsNothing);

    // Expand collapsed folders to reveal sessions
    await tester.tap(find.byKey(const ValueKey('session-folder:/repo')));
    await tester.tap(find.byKey(const ValueKey('session-folder:/other')));
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets('new session uses chosen working directory', (tester) async {
    final client = _SessionCreateClient();
    await tester.pumpWidget(
      wrapWithThemeAndScope(
        const SessionsSidebar(),
        overrides: [
          pcpClientProvider.overrideWithValue(client),
          sessionListProvider.overrideWith((ref) async => []),
          activeSessionIdProvider.overrideWith((ref) => null),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SessionsSidebar)),
    );
    expect(container.read(pcpClientProvider), same(client));
    await tester.tap(find.byTooltip('Nuova Sessione'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-session-cwd')),
      'C:/work/project',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crea'));
    await tester.pumpAndSettle();

    final create = client.commands.firstWhere(
      (command) => command.type == 'session.create',
    );
    expect(create.payload['cwd'], 'C:/work/project');
  });

  testWidgets('SessionTreeDialog renders properly in empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithThemeAndScope(const SessionTreeDialog(sessionId: 'sess_test')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Albero della Sessione'), findsOneWidget);
    expect(find.text('Sessione: sess_test'), findsOneWidget);
    expect(find.text('Chiudi'), findsOneWidget);
  });
}
