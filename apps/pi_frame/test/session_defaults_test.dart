import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/snapshot_reducer.dart';

class MockDefaultsPcpClient extends PcpClient {
  MockDefaultsPcpClient() : super(port: 1, token: 'test');

  @override
  Future<Map<String, dynamic>> getAvailableModels(String sessionId) async {
    return {
      'data': {
        'currentModel': {'id': 'claude-3-7-sonnet', 'name': 'Claude 3.7 Sonnet'},
        'currentThinkingLevel': 'high',
        'models': [
          {'id': 'claude-3-7-sonnet', 'name': 'Claude 3.7 Sonnet', 'isDefault': true},
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getAvailableThinkingLevels(String sessionId) async {
    return {
      'data': {
        'currentLevel': 'high',
        'levels': ['off', 'low', 'medium', 'high'],
      },
    };
  }
}

void main() {
  test('snapshot_reducer parses both Map and String model values', () {
    final payloadMap = {
      'session': {'id': 's1', 'name': 'Test'},
      'runtime': {'status': 'settled', 'model': {'id': 'model_map', 'name': 'Model Map'}},
      'queue': {},
    };
    final stateMap = applySessionSnapshot('s1', 1, payloadMap);
    expect(stateMap.currentModel, 'Model Map');

    final payloadString = {
      'session': {'id': 's2', 'name': 'Test'},
      'runtime': {'status': 'settled', 'model': 'claude-sonnet-str'},
      'queue': {},
    };
    final stateString = applySessionSnapshot('s2', 1, payloadString);
    expect(stateString.currentModel, 'claude-sonnet-str');
  });

  test('SessionStateNotifier.refreshDefaults populates model and thinking level defaults', () async {
    final client = MockDefaultsPcpClient();
    final notifier = SessionStateNotifier('s_test_defaults', client);

    expect(notifier.state.currentModel, isNull);

    await notifier.refreshDefaults();

    expect(notifier.state.currentModel, 'Claude 3.7 Sonnet');
    expect(notifier.state.currentThinkingLevel, 'high');
  });
}
