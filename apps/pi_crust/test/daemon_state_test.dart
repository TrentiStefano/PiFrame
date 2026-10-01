import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/data/daemon/pcp_client.dart';
import 'package:pi_crust/domain/session/agent_status.dart';
import 'package:pi_crust/domain/session/snapshot_reducer.dart';

class ListClient extends PcpClient {
  int calls = 0;
  ListClient() : super(port: 0, token: 'test');
  @override
  Future<Map<String, dynamic>> listSessions({String? query, int? limit}) async {
    calls++;
    return {'state': 'completed', 'data': {'sessions': [{'id': 'visible'}]}};
  }
}

void main() {
  test('session list refreshes when handshake completes', () async {
    final changes = StreamController<DaemonConnectionState>();
    final client = ListClient();
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      connectionStateProvider.overrideWith((ref) => changes.stream),
    ]);
    final listener = container.listen(sessionListProvider, (_, _) {});
    changes.add(DaemonConnectionState.disconnected);
    await Future<void>.delayed(Duration.zero);
    expect(await container.read(sessionListProvider.future), isEmpty);
    changes.add(DaemonConnectionState.connected);
    await Future<void>.delayed(Duration.zero);
    expect(await container.read(sessionListProvider.future), [{'id': 'visible'}]);
    expect(client.calls, 1);
    listener.close();
    container.dispose();
    client.dispose();
    await changes.close();
  });

  test('full snapshot restores runtime and nested Pi messages atomically', () {
    final state = applySessionSnapshot('test', 42, {
      'session': {'cwd': '/project', 'readOnly': true},
      'runtime': {'status': 'awaiting_user', 'queue': {'steering': ['later']}},
      'transcript': {'entries': [
        {'type': 'message', 'id': 'entry', 'timestamp': '2026-01-01T00:00:00Z',
          'message': {'role': 'user', 'content': 'History'}},
      ]},
      'liveMessage': {'content': [
        {'type': 'text', 'text': 'Streaming'},
        {'type': 'thinking', 'thinking': 'Reasoning'},
      ]},
      'activeTools': [{'toolCallId': 'call1', 'toolName': 'read', 'isRunning': true}],
      'pendingUiRequests': [{'requestId': 'ui1', 'options': ['Yes']}],
    });
    expect(state.entries.single.text, 'History');
    expect(state.entries.single.id, 'entry');
    expect(state.entries.single.timestamp, greaterThan(0));
    expect(state.agentStatus, AgentStatus.awaitingUser);
    expect(state.readOnly, true);
    expect(state.currentStreamingText, 'Streaming');
    expect(state.currentStreamingThinking, 'Reasoning');
    expect(state.activeToolCalls['call1']!.isRunning, true);
    expect(state.steeringQueue, ['later']);
    expect(state.pendingUiRequests.single['options'], ['Yes']);
    expect(state.lastAppliedSeq, 42);
    final empty = applySessionSnapshot('test', 0, {'transcript': {'entries': []}});
    expect(empty.entries, isEmpty);
    expect(empty.currentStreamingText, isEmpty);
    expect(empty.agentStatus, AgentStatus.settled);
  });
}
