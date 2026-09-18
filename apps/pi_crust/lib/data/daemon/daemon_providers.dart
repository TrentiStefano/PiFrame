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
final showSettingsProvider = StateProvider<bool>((ref) => false);

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
      final runtimeMeta = snapPayload['runtime'] as Map<String, dynamic>?;
      final usageMeta = snapPayload['usage'] as Map<String, dynamic>?;
      final transcriptMeta = snapPayload['transcript'] as Map<String, dynamic>?;

      final rawEntries = transcriptMeta?['entries'] as List<dynamic>? ?? [];
      final entries = rawEntries.map((e) {
        final map = e as Map<String, dynamic>;
        String text = '';
        if (map['text'] is String) {
          text = map['text'] as String;
        } else if (map['content'] is String) {
          text = map['content'] as String;
        } else if (map['content'] is List) {
          for (final b in (map['content'] as List)) {
            if (b is Map && b['type'] == 'text') {
              text += (b['text'] as String?) ?? '';
            }
          }
        }
        return SessionEntry(
          id: map['id']?.toString() ?? '',
          role: map['role']?.toString() ?? 'assistant',
          text: text,
          timestamp: (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        );
      }).toList();

      state = state.copyWith(
        sessionName: sessionMeta?['name'] as String?,
        cwd: sessionMeta?['cwd'] as String? ?? '',
        entries: entries.isNotEmpty ? entries : state.entries,
        currentModel: runtimeMeta?['model'] is Map
            ? (runtimeMeta!['model']['name'] ?? runtimeMeta['model']['id'])?.toString()
            : null,
        currentThinkingLevel: runtimeMeta?['thinkingLevel']?.toString(),
        usage: usageMeta,
        lastAppliedSeq: snapshot.seq,
      );
    });

    _sub = client!.events(sessionId).listen((event) {
      state = reduceSessionState(state, event);
    });
  }

  Future<void> sendPrompt(String text, {String? streamingBehavior}) async {
    if (client == null) return;
    await client!.sendPrompt(sessionId, text, streamingBehavior: streamingBehavior);
  }

  Future<Map<String, dynamic>?> interrupt() async {
    if (client == null) return null;
    return client!.interruptAgent(sessionId);
  }

  Future<void> clearQueue() async {
    if (client == null) return;
    await client!.clearQueue(sessionId);
  }

  Future<Map<String, dynamic>?> compact() async {
    if (client == null) return null;
    return client!.compactContext(sessionId);
  }

  Future<void> setModel(String provider, String modelId) async {
    if (client == null) return;
    await client!.setModel(sessionId, provider, modelId);
  }

  Future<void> setThinkingLevel(String level) async {
    if (client == null) return;
    await client!.setThinkingLevel(sessionId, level);
  }

  Future<void> recoverSession() async {
    if (client == null) return;
    await client!.recoverSession(sessionId);
  }

  Future<List<Map<String, dynamic>>> getCommands() async {
    if (client == null) return [];
    try {
      final res = await client!.getCommands(sessionId);
      final data = res['data'] as Map<String, dynamic>?;
      final cmds = (data?['commands'] ?? res['commands']) as List<dynamic>?;
      return cmds?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableModels() async {
    if (client == null) return [];
    try {
      final res = await client!.getAvailableModels(sessionId);
      final data = res['data'] as Map<String, dynamic>?;
      final models = (data?['models'] ?? res['models']) as List<dynamic>?;
      return models?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> getAvailableThinkingLevels() async {
    if (client == null) return [];
    try {
      final res = await client!.getAvailableThinkingLevels(sessionId);
      final data = res['data'] as Map<String, dynamic>?;
      final levels = (data?['levels'] ?? res['levels']) as List<dynamic>?;
      return levels?.map((e) => e.toString()).toList() ?? [];
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _snapSub?.cancel();
    super.dispose();
  }
}
