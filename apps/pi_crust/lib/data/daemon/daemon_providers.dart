import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_protocol/pi_crust_protocol.dart';
import '../../domain/session/session_state.dart';
import '../../domain/session/session_reducer.dart';
import 'pcp_client.dart';
import 'daemon_locator.dart';

final daemonEndpointProvider = FutureProvider<DaemonEndpoint?>((ref) async {
  return DaemonLocator.locateOrProbe();
});

final pcpClientProvider = Provider<PcpClient?>((ref) {
  final endpointAsync = ref.watch(daemonEndpointProvider);
  return endpointAsync.when(
    data: (endpoint) {
      if (endpoint == null) return null;
      final client = PcpClient(port: endpoint.port, token: endpoint.token);
      client.connect();
      ref.onDispose(() => client.dispose());
      return client;
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

final connectionStateProvider = StreamProvider<DaemonConnectionState>((ref) {
  final client = ref.watch(pcpClientProvider);
  if (client == null) return Stream.value(DaemonConnectionState.disconnected);
  return client.connectionStateStream;
});

final sessionListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(pcpClientProvider);
  if (client == null || client.state != DaemonConnectionState.connected) {
    return [];
  }

  final cmd = PcpCommand(
    protocol: 1,
    id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
    ts: DateTime.now().millisecondsSinceEpoch,
    commandId: 'list_${DateTime.now().millisecondsSinceEpoch}',
    type: 'session.list',
    payload: {},
  );

  try {
    final res = await client.sendCommand(cmd);
    final data = res['data'] as Map<String, dynamic>?;
    final sessions = data?['sessions'] as List?;
    return sessions?.cast<Map<String, dynamic>>() ?? [];
  } catch (_) {
    return [];
  }
});

final activeSessionIdProvider = StateProvider<String?>((ref) => null);

final sessionStateFamily = StateNotifierProvider.family<SessionStateNotifier, SessionState, String>((ref, sessionId) {
  final client = ref.watch(pcpClientProvider);
  return SessionStateNotifier(sessionId, client);
});

class SessionStateNotifier extends StateNotifier<SessionState> {
  final String sessionId;
  final PcpClient? client;
  StreamSubscription? _sub;
  StreamSubscription? _snapSub;

  SessionStateNotifier(this.sessionId, this.client)
      : super(SessionState(sessionId: sessionId, cwd: '')) {
    _init();
  }

  void _init() {
    if (client == null) return;

    client!.attach(sessionId);

    _snapSub = client!.snapshots(sessionId).listen((snapshot) {
      final snapPayload = snapshot.payload;
      final sessionMeta = snapPayload['session'] as Map<String, dynamic>?;

      state = state.copyWith(
        sessionName: sessionMeta?['name'] as String?,
        cwd: sessionMeta?['cwd'] as String? ?? '',
        lastAppliedSeq: snapshot.seq,
      );
    });

    _sub = client!.events(sessionId).listen((event) {
      state = reduceSessionState(state, event);
    });
  }

  Future<void> sendPrompt(String text, {String? streamingBehavior}) async {
    if (client == null) return;
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: 'prm_${DateTime.now().millisecondsSinceEpoch}',
      type: 'agent.prompt',
      payload: {
        'text': text,
        'streamingBehavior': ?streamingBehavior,
      },
    );
    await client!.sendCommand(cmd);
  }

  Future<void> interrupt() async {
    if (client == null) return;
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: 'int_${DateTime.now().millisecondsSinceEpoch}',
      type: 'agent.interrupt',
      payload: {},
    );
    await client!.sendCommand(cmd);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _snapSub?.cancel();
    super.dispose();
  }
}
