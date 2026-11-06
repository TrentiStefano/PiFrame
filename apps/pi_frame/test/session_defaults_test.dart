import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/snapshot_reducer.dart';

class MockDefaultsPcpClient extends PcpClient {
  MockDefaultsPcpClient() : super(port: 1, token: 'test');

  @override
  Future<Map<String, dynamic>> getAvailableModels(String sessionId) async {
    return {
      'data': {
        'currentModel': {
          'provider': 'anthropic',
          'id': 'claude-3-7-sonnet',
          'name': 'Claude 3.7 Sonnet',
        },
        'currentThinkingLevel': 'high',
        'models': [
          {
            'provider': 'anthropic',
            'id': 'claude-3-7-sonnet',
            'name': 'Claude 3.7 Sonnet',
            'isDefault': true,
          },
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
  test('current model matching includes provider and id', () {
    const state = SessionState(
      sessionId: 's1',
      cwd: '',
      currentModel: 'Shared',
      currentModelProvider: 'anthropic',
      currentModelId: 'shared-id',
    );
    expect(
      state.matchesModel({
        'provider': 'anthropic',
        'id': 'shared-id',
        'name': 'Shared',
      }),
      isTrue,
    );
    expect(
      state.matchesModel({
        'provider': 'github-copilot',
        'id': 'shared-id',
        'name': 'Shared',
      }),
      isFalse,
    );
  });

  test('snapshot_reducer parses both Map and String model values', () {
    final payloadMap = {
      'session': {'id': 's1', 'name': 'Test'},
      'runtime': {
        'status': 'settled',
        'model': {
          'provider': 'anthropic',
          'id': 'model_map',
          'name': 'Model Map',
        },
      },
      'queue': {},
    };
    final stateMap = applySessionSnapshot('s1', 1, payloadMap);
    expect(stateMap.currentModel, 'Model Map');
    expect(stateMap.currentModelProvider, 'anthropic');
    expect(stateMap.currentModelId, 'model_map');

    final payloadString = {
      'session': {'id': 's2', 'name': 'Test'},
      'runtime': {'status': 'settled', 'model': 'claude-sonnet-str'},
      'queue': {},
    };
    final stateString = applySessionSnapshot('s2', 1, payloadString);
    expect(stateString.currentModel, 'claude-sonnet-str');
    expect(stateString.currentModelProvider, isNull);
    expect(stateString.currentModelId, isNull);
  });

  test('SessionStateNotifier.refreshDefaults populates model and thinking level defaults', () async {
    final client = MockDefaultsPcpClient();
    final notifier = SessionStateNotifier('s_test_defaults', client);

    expect(notifier.state.currentModel, isNull);

    await notifier.refreshDefaults();

    expect(notifier.state.currentModel, 'Claude 3.7 Sonnet');
    expect(notifier.state.currentModelProvider, 'anthropic');
    expect(notifier.state.currentModelId, 'claude-3-7-sonnet');
    expect(notifier.state.currentThinkingLevel, 'high');
  });
}
