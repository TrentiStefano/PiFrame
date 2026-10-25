import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/theme/theme_providers.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _MockPcpClient extends PcpClient {
  _MockPcpClient() : super(port: 1, token: 'test');

  @override
  Stream<PcpEvent> events(String sessionId) => const Stream.empty();

  @override
  Stream<PcpSnapshot> snapshots(String sessionId) => const Stream.empty();

  @override
  Future<Map<String, dynamic>> sendCommand(PcpCommand command) async => {
        'status': 'ok',
        'data': {},
      };
}

void main() {
  testWidgets('Landing page displays top 5 recent active sessions and switches session on tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = _MockPcpClient();
    final testSessions = [
      {
        'id': 'session-1',
        'name': 'Refactor Core Engine',
        'cwd': '/projects/pi-core',
        'updatedAt': 1700000000500,
      },
      {
        'id': 'session-2',
        'name': 'Fix Flutter UI Bug',
        'cwd': '/projects/pi-crust',
        'updatedAt': 1700000000400,
      },
      {
        'id': 'subagent-worker-1',
        'name': 'worker#1 subagent',
        'cwd': '/projects/sub',
        'isSubsession': true,
        'updatedAt': 1700000000350,
      },
      {
        'id': 'session-3',
        'name': 'Database Migrations',
        'cwd': '/projects/backend',
        'updatedAt': 1700000000300,
      },
      {
        'id': 'session-4',
        'name': 'Documentation Pass',
        'cwd': '/projects/docs',
        'updatedAt': 1700000000200,
      },
      {
        'id': 'session-5',
        'name': 'API Integration',
        'cwd': '/projects/api',
        'updatedAt': 1700000000100,
      },
      {
        'id': 'session-6',
        'name': 'Older Session',
        'cwd': '/projects/old',
        'updatedAt': 1700000000050,
      },
    ];

    final container = ProviderContainer(
      overrides: [
        pcpClientProvider.overrideWithValue(mockClient),
        connectionStateProvider.overrideWith(
          (ref) => Stream.value(DaemonConnectionState.connected),
        ),
        sessionListProvider.overrideWith((ref) => Future.value(testSessions)),
        themeStorageProvider.overrideWithValue(MemoryThemeStorage('piframe-dark')),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify recent sessions title is present
    expect(find.text('Sessioni recenti'), findsOneWidget);
    expect(find.text('Quick Launch'), findsOneWidget);

    // Verify the top 5 sessions are rendered
    expect(find.text('Refactor Core Engine'), findsOneWidget);
    expect(find.text('Fix Flutter UI Bug'), findsOneWidget);
    expect(find.text('Database Migrations'), findsOneWidget);
    expect(find.text('Documentation Pass'), findsOneWidget);
    expect(find.text('API Integration'), findsOneWidget);

    // Subagent/worker must be excluded
    expect(find.text('worker#1 subagent'), findsNothing);

    // 6th session must be excluded (only latest 5)
    expect(find.text('Older Session'), findsNothing);

    // Tap on session-2 tile to switch to it
    final session2Tile = find.byKey(const ValueKey('quick-launch-session-session-2'));
    expect(session2Tile, findsOneWidget);
    await tester.tap(session2Tile);
    await tester.pump();

    // Now activeSessionIdProvider should be 'session-2'
    expect(container.read(activeSessionIdProvider), 'session-2');
  });
}
