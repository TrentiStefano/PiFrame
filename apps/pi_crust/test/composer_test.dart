import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/domain/session/agent_status.dart';
import 'package:pi_crust/features/composer/composer.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

void main() {
  testWidgets('Composer displays Invia button when agent is settled', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStateFamily('s_test').overrideWith(
            (ref) => SessionStateNotifier('s_test', null)
              ..state = const SessionState(
                sessionId: 's_test',
                cwd: '/test',
                agentStatus: AgentStatus.settled,
              ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [CrustTokens.dark],
          ),
          home: const Scaffold(
            body: Composer(sessionId: 's_test'),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    // Verify arrow_upward icon (Invia) is present
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    // Verify Steer and Follow-up buttons are NOT present when idle
    expect(find.text('Steer'), findsNothing);
    expect(find.text('Follow-up'), findsNothing);
  });

  testWidgets('Composer displays Steer and Follow-up buttons when agent is streaming', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStateFamily('s_test').overrideWith(
            (ref) => SessionStateNotifier('s_test', null)
              ..state = const SessionState(
                sessionId: 's_test',
                cwd: '/test',
                agentStatus: AgentStatus.working,
                streamingTextBlocks: {0: 'Hello, '},
              ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [CrustTokens.dark],
          ),
          home: const Scaffold(
            body: Composer(sessionId: 's_test'),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    // Steer & Follow-up buttons should now be visible
    expect(find.text('Steer'), findsOneWidget);
    expect(find.text('Follow-up'), findsOneWidget);
    // Stop button should be visible
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
  });

  testWidgets('Composer displays pending queue bar when queue is non-empty', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStateFamily('s_test').overrideWith(
            (ref) => SessionStateNotifier('s_test', null)
              ..state = const SessionState(
                sessionId: 's_test',
                cwd: '/test',
                agentStatus: AgentStatus.working,
                steeringQueue: ['Steer task 1'],
                followUpQueue: ['Follow-up task 2'],
              ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [CrustTokens.dark],
          ),
          home: const Scaffold(
            body: Composer(sessionId: 's_test'),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('In coda (2): 1 steer, 1 follow-up'), findsOneWidget);
    expect(find.text('Svuota coda'), findsOneWidget);
  });
}
