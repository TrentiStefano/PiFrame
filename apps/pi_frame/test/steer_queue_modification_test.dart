import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class MockSteerQueueClient extends PcpClient {
  MockSteerQueueClient() : super(port: 1, token: 'test');

  final List<PcpCommand> commands = [];

  @override
  Future<Map<String, dynamic>> sendCommand(PcpCommand command) async {
    commands.add(command);
    return {'data': {}};
  }
}

void main() {
  testWidgets('Composer displays queued steer messages and allows modifying them', (
    tester,
  ) async {
    final client = MockSteerQueueClient();
    final notifier = SessionStateNotifier('sess_steer', client)
      ..state = SessionState(
        sessionId: 'sess_steer',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        steeringQueue: ['Refactor module X', 'Add unit tests'],
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          pcpClientProvider.overrideWithValue(client),
          sessionStateFamily('sess_steer').overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: Composer(sessionId: 'sess_steer')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Composer));
    await tester.pumpAndSettle();

    // Verify queue bar is visible with the 2 queued items
    expect(find.byKey(const ValueKey('composer-queue-bar')), findsOneWidget);
    expect(find.text('Refactor module X'), findsOneWidget);
    expect(find.text('Add unit tests'), findsOneWidget);

    // Verify edit and delete buttons for item 0
    final editBtn0 = find.byKey(const ValueKey('edit-steer-btn-0'));
    final deleteBtn0 = find.byKey(const ValueKey('delete-steer-btn-0'));
    expect(editBtn0, findsOneWidget);
    expect(deleteBtn0, findsOneWidget);

    // Tap edit on the first steer message
    await tester.tap(editBtn0);
    await tester.pumpAndSettle();

    // Verify edit dialog opened
    expect(find.byKey(const ValueKey('edit-steer-dialog-field')), findsOneWidget);
    expect(find.text('Refactor module X'), findsNWidgets(2)); // in queue bar and dialog field

    // Update text in dialog
    await tester.enterText(
      find.byKey(const ValueKey('edit-steer-dialog-field')),
      'Refactor module X with new architecture',
    );
    await tester.pumpAndSettle();

    // Tap Save
    await tester.tap(find.byKey(const ValueKey('edit-steer-dialog-save')));
    await tester.pumpAndSettle();

    // Verify notifier state was updated
    expect(
      notifier.state.steeringQueue,
      ['Refactor module X with new architecture', 'Add unit tests'],
    );

    // Now delete the second steer message
    final deleteBtn1 = find.byKey(const ValueKey('delete-steer-btn-1'));
    await tester.tap(deleteBtn1);
    await tester.pumpAndSettle();

    expect(
      notifier.state.steeringQueue,
      ['Refactor module X with new architecture'],
    );
  });
}
