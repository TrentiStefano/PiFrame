import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/transcript/subagents_provider.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _CostClient extends PcpClient {
  _CostClient() : super(port: 0, token: 'test');
  double cost = 0.0175;
  int calls = 0;

  @override
  DaemonConnectionState get state => DaemonConnectionState.connected;

  @override
  Future<List<Map<String, dynamic>>> getSubagents(String sessionId) async {
    calls++;
    return [
      {
        'id': 'worker#1',
        'name': 'Reviewer',
        'model': 'test-model',
        'cost': cost,
        'status': 'completed',
        'output': 'Review in progress',
      },
    ];
  }
}

void main() {
  testWidgets('daemon costs keep refreshing in cards and the open cost popup', (
    tester,
  ) async {
    final client = _CostClient();
    final notifier = SessionStateNotifier('costs', null)
      ..state = const SessionState(
        sessionId: 'costs',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        sessionStats: {'cost': 0.02},
      );
    final container = ProviderContainer(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        pcpClientProvider.overrideWithValue(client),
        sessionStateFamily('costs').overrideWith((ref) => notifier),
      ],
    );
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: TranscriptView(sessionId: 'costs')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(subagentsFamily('costs')).single.cost, 0.0175);
    await tester.tap(find.byKey(const ValueKey('subagents-book-tab')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('\$0.0175'), findsWidgets);

    await tester.tap(find.textContaining('\$0.0375'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey('cost-breakdown-subagents-row')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Costi Subagenti & Modelli'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('\$0.0175')),
      findsNWidgets(2),
    );

    final callsBefore = client.calls;
    client.cost = 0.0425;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(client.calls, greaterThan(callsBefore));
    expect(container.read(subagentsFamily('costs')).single.cost, 0.0425);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('\$0.0425')),
      findsNWidgets(2),
    );
    await tester.tap(find.byKey(const ValueKey('cost-breakdown-back-btn')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('\$0.0625')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('cost-breakdown-close-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('\$0.0425'), findsWidgets);
    expect(find.textContaining('\$0.0625'), findsOneWidget);

    // A settled parent with no running children no longer needs polling.
    notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.settled);
    await tester.pumpAndSettle();
    final settledCalls = client.calls;
    await tester.pump(const Duration(seconds: 10));
    expect(client.calls, settledCalls);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
