import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/data/daemon/pcp_client.dart';
import 'package:pi_crust/domain/session/session_state.dart';

class _StatsClient extends PcpClient {
  _StatsClient() : super(port: 1, token: 'test');

  @override
  void attach(String sessionId, {int? lastSeq}) {}

  @override
  Future<Map<String, dynamic>> getSessionStats(String sessionId) async => {
    'data': {
      'tokens': {'total': 42000},
      'cost': 0.42,
      'contextUsage': {
        'tokens': 70656,
        'contextWindow': 128000,
        'percent': 55.2,
      },
    },
  };
}

void main() {
  test(
    'session notifier exposes Pi cumulative stats without reshaping them',
    () async {
      final client = _StatsClient();
      final notifier = SessionStateNotifier('session-a', client)
        ..state = const SessionState(
          sessionId: 'session-a',
          cwd: '/repo',
          currentModel: 'test-model',
        );
      addTearDown(() {
        notifier.dispose();
        client.dispose();
      });

      await notifier.refreshSessionStats();
      expect(notifier.state.sessionStats?['cost'], 0.42);
      expect(notifier.state.sessionStats?['tokens']['total'], 42000);
      expect(notifier.state.sessionStats?['contextUsage']['percent'], 55.2);
    },
  );
}
