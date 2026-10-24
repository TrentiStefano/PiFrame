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

class MockInterruptClient extends PcpClient {
  MockInterruptClient() : super(port: 1, token: 'test');

  final List<PcpCommand> commands = [];

  @override
  Future<Map<String, dynamic>> sendCommand(PcpCommand command) async {
    commands.add(command);
    if (command.type == 'agent.interrupt') {
      return {
        'data': {
          'interrupted': true,
          'queue': {'steering': <String>[], 'followUp': <String>[]},
        },
      };
    }
    if (command.type == 'agent.clearQueue') {
      return {'data': {}};
    }
    if (command.type == 'agent.prompt') {
      return {'data': {'runId': 'run_1'}};
    }
    return {'data': {}};
  }
}

void main() {
  test('SessionStateNotifier.interrupt clears queues and settles state', () async {
    final client = MockInterruptClient();
    final notifier = SessionStateNotifier('s_int', client)
      ..state = SessionState(
        sessionId: 's_int',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        steeringQueue: const ['Prior steer command'],
        followUpQueue: const ['Follow up command'],
        streamingTextBlocks: const {0: 'Generating...'},
      );

    expect(notifier.state.isStreaming, isTrue);
    expect(notifier.state.steeringQueue, isNotEmpty);

    final res = await notifier.interrupt();
    expect(res, isNotNull);
    expect(notifier.state.steeringQueue, isEmpty);
    expect(notifier.state.followUpQueue, isEmpty);
    expect(notifier.state.agentStatus, AgentStatus.settled);
    expect(notifier.state.isStreaming, isFalse);
    expect(client.commands.any((c) => c.type == 'agent.interrupt'), isTrue);
  });

  test('SessionStateNotifier.clearQueue clears queues', () async {
    final client = MockInterruptClient();
    final notifier = SessionStateNotifier('s_int', client)
      ..state = SessionState(
        sessionId: 's_int',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        steeringQueue: const ['Steer 1'],
        followUpQueue: const ['Follow 1'],
      );

    await notifier.clearQueue();
    expect(notifier.state.steeringQueue, isEmpty);
    expect(notifier.state.followUpQueue, isEmpty);
    expect(client.commands.any((c) => c.type == 'agent.clearQueue'), isTrue);
  });

  testWidgets(
    'Composer interrupt cancels steer queue without injecting cancelled text into composer',
    (tester) async {
      final client = MockInterruptClient();
      final notifier = SessionStateNotifier('s_ui_int', client)
        ..state = SessionState(
          sessionId: 's_ui_int',
          cwd: '/repo',
          agentStatus: AgentStatus.working,
          steeringQueue: const ['Steer that was queued earlier'],
          streamingTextBlocks: const {0: 'Generating response...'},
          entries: const [],
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            pcpClientProvider.overrideWithValue(client),
            sessionStateFamily('s_ui_int').overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(body: Composer(sessionId: 's_ui_int')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap minimized bar to expand controls
      await tester.tap(find.byKey(const ValueKey('composer-minimized-bar')));
      await tester.pumpAndSettle();

      // Verify stop button is visible
      final stopBtn = find.byIcon(Icons.stop_circle_outlined);
      expect(stopBtn, findsOneWidget);

      // Trigger interrupt
      await tester.tap(stopBtn);
      await tester.pumpAndSettle();

      // Verify that the cancelled steer message is NOT restored into the composer text field
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isEmpty);

      // Verify snackbar feedback
      expect(
        find.text('Agente interrotto. La coda di messaggi è stata cancellata.'),
        findsOneWidget,
      );

      // Verify notifier state cleared queues
      expect(notifier.state.steeringQueue, isEmpty);

      // Enter a new prompt and send it
      await tester.enterText(find.byType(TextField), 'Fresh new prompt');
      await tester.pumpAndSettle();

      final sendBtn = find.byIcon(Icons.arrow_upward);
      expect(sendBtn, findsOneWidget);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      // Check the prompt command sent
      final promptCmd = client.commands.firstWhere(
        (c) => c.type == 'agent.prompt',
      );
      expect(promptCmd.payload['text'], 'Fresh new prompt');
      expect(promptCmd.payload['text'], isNot(contains('Steer that was queued earlier')));
    },
  );
}
