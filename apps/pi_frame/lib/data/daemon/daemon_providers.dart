import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';
import '../../domain/session/session_reducer.dart';
import '../../domain/session/snapshot_reducer.dart';
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
      final client = PcpClient(
        host: endpoint.host,
        port: endpoint.port,
        token: endpoint.token,
        isSecure: endpoint.isSecure,
        rediscover: () async {
          final found = await DaemonLocator.locateOrProbe();
          return found == null ? null : (port: found.port, token: found.token);
        },
      );
      client.connect();
      ref.onDispose(() => client.dispose());
      return client;
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

final connectionStateProvider = StreamProvider<DaemonConnectionState>((
  ref,
) async* {
  final client = ref.watch(pcpClientProvider);
  if (client == null) {
    yield DaemonConnectionState.disconnected;
    return;
  }
  yield client.state;
  yield* client.connectionStateStream;
});

final sessionListProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final client = ref.watch(pcpClientProvider);
  final connection = ref.watch(connectionStateProvider);
  if (client == null || connection.value != DaemonConnectionState.connected) {
    return [];
  }

  final subscription = client.events('@daemon').listen((event) {
    if (event.type == 'session.indexChanged') {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(subscription.cancel);

  try {
    final res = await client.listSessions().timeout(const Duration(seconds: 8));
    final data = res['data'] as Map<String, dynamic>? ?? res;
    final sessions =
        (data['sessions'] as List? ?? res['sessions'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    return sessions;
  } catch (_) {
    return [];
  }
});

final activeSessionIdProvider = StateProvider<String?>((ref) => null);
final showSettingsProvider = StateProvider<bool>((ref) => false);
final settingsTabIndexProvider = StateProvider<int>((ref) => 0);

final sessionStateFamily =
    StateNotifierProvider.family<SessionStateNotifier, SessionState, String>((
      ref,
      sessionId,
    ) {
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

    _snapSub = client!.snapshots(sessionId).listen((snapshot) {
      final nextState = applySessionSnapshot(
        sessionId,
        snapshot.seq,
        snapshot.payload,
      );
      state = nextState;
      unawaited(refreshSessionStats());
      unawaited(refreshDefaults());
    });

    _sub = client!.events(sessionId).listen((event) {
      state = reduceSessionState(state, event);
      if (event.type == 'usage.updated' ||
          event.type == 'run.settled' ||
          event.type == 'message.completed' ||
          event.type == 'turn.ended' ||
          event.type == 'tool.completed') {
        unawaited(refreshSessionStats());
      }
    });
    client!.attach(sessionId);
  }

  bool _defaultsLoading = false;

  Future<void> refreshDefaults() async {
    if (client == null || state.readOnly || _defaultsLoading) return;
    final needsModel =
        state.currentModel == null || state.currentModel!.isEmpty;
    final needsThinking =
        state.currentThinkingLevel == null ||
        state.currentThinkingLevel!.isEmpty;
    if (!needsModel && !needsThinking) return;

    _defaultsLoading = true;
    try {
      String? resolvedModel;
      String? resolvedThinking;

      if (needsModel) {
        final res = await client!
            .getAvailableModels(sessionId)
            .timeout(const Duration(seconds: 4));
        final data = res['data'] as Map<String, dynamic>? ?? res;
        final currentModelRaw = data['currentModel'] ?? data['model'];
        if (currentModelRaw is Map) {
          resolvedModel = (currentModelRaw['name'] ?? currentModelRaw['id'])
              ?.toString();
        } else if (currentModelRaw is String && currentModelRaw.isNotEmpty) {
          resolvedModel = currentModelRaw;
        }

        if (resolvedModel == null || resolvedModel.isEmpty) {
          final models =
              (data['models'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          final defaultModel = models.firstWhere(
            (m) => m['isDefault'] == true || m['default'] == true,
            orElse: () => models.isNotEmpty ? models.first : const {},
          );
          if (defaultModel.isNotEmpty) {
            resolvedModel = (defaultModel['name'] ?? defaultModel['id'])
                ?.toString();
          }
        }

        if (needsThinking && data['currentThinkingLevel'] != null) {
          resolvedThinking = data['currentThinkingLevel'].toString();
        }
      }

      if (needsThinking &&
          (resolvedThinking == null || resolvedThinking.isEmpty)) {
        final tRes = await client!
            .getAvailableThinkingLevels(sessionId)
            .timeout(const Duration(seconds: 4));
        final tData = tRes['data'] as Map<String, dynamic>? ?? tRes;
        final levelRaw =
            tData['currentLevel'] ??
            tData['thinkingLevel'] ??
            tData['defaultLevel'];
        if (levelRaw != null) {
          resolvedThinking = levelRaw.toString();
        } else {
          final levels =
              (tData['levels'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          if (levels.contains('medium')) {
            resolvedThinking = 'medium';
          } else if (levels.isNotEmpty) {
            resolvedThinking = levels.first;
          } else {
            resolvedThinking = 'medium';
          }
        }
      }

      if (mounted && (resolvedModel != null || resolvedThinking != null)) {
        state = state.copyWith(
          currentModel: resolvedModel ?? state.currentModel,
          currentThinkingLevel: resolvedThinking ?? state.currentThinkingLevel,
        );
      }
    } catch (_) {
      // Daemon may not support getAvailableModels or offline
    } finally {
      _defaultsLoading = false;
    }
  }

  bool _statsLoading = false;
  bool _hasPendingStatsRefresh = false;

  Future<void> refreshSessionStats() async {
    if (client == null || state.readOnly) {
      return;
    }
    if (_statsLoading) {
      _hasPendingStatsRefresh = true;
      return;
    }
    _statsLoading = true;
    try {
      final result = await client!.getSessionStats(sessionId);
      final data = result['data'] as Map<String, dynamic>? ?? result;
      if (mounted) {
        final updatedData = Map<String, dynamic>.from(data);
        if (state.contextWindowOverride != null &&
            state.contextWindowOverride! > 0) {
          final cu = updatedData['contextUsage'] as Map?;
          final tokens = (cu?['tokens'] as num?)?.toDouble();
          final win = state.contextWindowOverride!;
          final pct = tokens == null ? null : (tokens / win) * 100.0;
          updatedData['contextUsage'] = {
            if (cu != null) ...Map<String, dynamic>.from(cu),
            'contextWindow': win,
            'percent': pct,
            'tokens': tokens?.toInt(),
          };
        }
        state = state.copyWith(sessionStats: updatedData);
      }
    } catch (_) {
      // Older Pi/agentd builds may not expose session statistics.
    } finally {
      _statsLoading = false;
      if (_hasPendingStatsRefresh) {
        _hasPendingStatsRefresh = false;
        unawaited(refreshSessionStats());
      }
    }
  }

  String _newPromptEntryId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var id = 'usr_$now';
    while (state.entries.any((entry) => entry.id == id)) {
      id = '${id}_';
    }
    return id;
  }

  void _markPromptFailed(String text, String message, {String? entryId}) {
    final index = entryId == null
        ? -1
        : state.entries.indexWhere((entry) => entry.id == entryId);
    final targetIndex = index >= 0
        ? index
        : state.entries.lastIndexWhere(
            (entry) => entry.role == 'user' && entry.text == text,
          );
    if (!mounted || targetIndex < 0) return;
    final entries = List<SessionEntry>.from(state.entries);
    final entry = entries[targetIndex];
    entries[targetIndex] = SessionEntry(
      id: entry.id,
      role: entry.role,
      text: entry.text,
      thinking: entry.thinking,
      toolCalls: entry.toolCalls,
      timestamp: entry.timestamp,
      metadata: {...?entry.metadata, 'sendError': message},
    );
    state = state.copyWith(entries: entries);
  }

  SessionEntry? removeFailedPrompt(String entryId) {
    final index = state.entries.indexWhere((entry) => entry.id == entryId);
    if (index < 0 || state.entries[index].metadata?['sendError'] is! String) {
      return null;
    }
    final entry = state.entries[index];
    final entries = List<SessionEntry>.from(state.entries)..removeAt(index);
    state = state.copyWith(entries: entries);
    return entry;
  }

  Future<void> retryFailedPrompt(String entryId) async {
    final index = state.entries.indexWhere((entry) => entry.id == entryId);
    if (index < 0 || state.entries[index].metadata?['sendError'] is! String) {
      return;
    }
    final previousStatus = state.agentStatus;
    final entry = state.entries[index];
    final retryId = _newPromptEntryId();
    final entries = List<SessionEntry>.from(state.entries);
    entries[index] = SessionEntry(
      id: retryId,
      role: entry.role,
      text: entry.text,
      thinking: entry.thinking,
      toolCalls: entry.toolCalls,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      metadata: {...?entry.metadata, 'sendError': null},
    );
    state = state.copyWith(entries: entries, agentStatus: AgentStatus.working);
    try {
      final promptClient = client;
      if (promptClient == null) throw StateError('Daemon non connesso');
      await promptClient.sendPrompt(sessionId, entry.text);
    } catch (error) {
      _markPromptFailed(
        entry.text,
        error.toString().replaceFirst(RegExp(r'^(Bad state|Exception):\s*'), ''),
        entryId: retryId,
      );
      if (mounted) state = state.copyWith(agentStatus: previousStatus);
    }
  }

  Future<void> sendPrompt(String text, {String? streamingBehavior}) async {
    final promptClient = client;

    if (streamingBehavior != null && promptClient == null) {
      throw StateError('Daemon non connesso');
    }

    final prevStatus = state.agentStatus;
    final optimisticId = streamingBehavior == null ? _newPromptEntryId() : null;
    if (optimisticId != null) {
      final userEntry = SessionEntry(
        id: optimisticId,
        role: 'user',
        text: text,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      state = state.copyWith(
        entries: [...state.entries, userEntry],
        agentStatus: AgentStatus.working,
      );
    }
    try {
      if (promptClient == null) throw StateError('Daemon non connesso');
      await promptClient.sendPrompt(
        sessionId,
        text,
        streamingBehavior: streamingBehavior,
      );
    } catch (error) {
      if (mounted && optimisticId != null) {
        _markPromptFailed(
          text,
          error.toString().replaceFirst(RegExp(r'^(Bad state|Exception):\s*'), ''),
          entryId: optimisticId,
        );
        state = state.copyWith(agentStatus: prevStatus);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> interrupt() async {
    if (client == null) return null;
    final res = await client!.interruptAgent(sessionId);
    if (mounted) {
      state = state.copyWith(
        steeringQueue: const [],
        followUpQueue: const [],
        agentStatus: AgentStatus.settled,
        streamingTextBlocks: const {},
        streamingThinkingBlocks: const {},
        activeToolCalls: const {},
      );
    }
    return res;
  }

  Future<void> rename(String newName) async {
    if (client != null) {
      await client!.renameSession(sessionId, newName);
    }
    if (mounted) {
      state = state.copyWith(sessionName: newName);
    }
  }

  Future<void> clearQueue() async {
    if (client == null) return;
    await client!.clearQueue(sessionId);
    if (mounted) {
      state = state.copyWith(steeringQueue: const [], followUpQueue: const []);
    }
  }

  Future<void> updateSteerMessage(int index, String newText) async {
    if (client == null) return;
    final currentSteering = List<String>.from(state.steeringQueue);
    final currentFollowUp = List<String>.from(state.followUpQueue);
    if (index < 0 || index >= currentSteering.length) return;

    await client!.clearQueue(sessionId);
    currentSteering[index] = newText;
    for (final msg in currentSteering) {
      await client!.sendPrompt(sessionId, msg, streamingBehavior: 'steer');
    }
    for (final msg in currentFollowUp) {
      await client!.sendPrompt(sessionId, msg, streamingBehavior: 'followUp');
    }
    state = state.copyWith(steeringQueue: currentSteering);
  }

  Future<void> removeSteerMessage(int index) async {
    if (client == null) return;
    final currentSteering = List<String>.from(state.steeringQueue);
    final currentFollowUp = List<String>.from(state.followUpQueue);
    if (index < 0 || index >= currentSteering.length) return;

    await client!.clearQueue(sessionId);
    currentSteering.removeAt(index);
    for (final msg in currentSteering) {
      await client!.sendPrompt(sessionId, msg, streamingBehavior: 'steer');
    }
    for (final msg in currentFollowUp) {
      await client!.sendPrompt(sessionId, msg, streamingBehavior: 'followUp');
    }
    state = state.copyWith(steeringQueue: currentSteering);
  }

  Future<Map<String, dynamic>?> compact() async {
    if (client == null) return null;
    return client!.compactContext(sessionId);
  }

  Future<void> setModel(String provider, String modelId) async {
    if (client == null) return;
    final result = await client!.setModel(sessionId, provider, modelId);
    final data = result['data'] as Map<String, dynamic>? ?? result;
    final model = data['model'] as Map<String, dynamic>? ?? data;
    state = state.copyWith(
      currentModel: (model['name'] ?? model['id'] ?? modelId).toString(),
    );
    client!.attach(sessionId, lastSeq: null);
  }

  Future<void> setThinkingLevel(String level) async {
    if (client == null) return;
    await client!.setThinkingLevel(sessionId, level);
    state = state.copyWith(currentThinkingLevel: level);
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
    try {
      return (await getAvailableModelsWithWarning()).models;
    } catch (_) {
      return [];
    }
  }

  Future<({List<Map<String, dynamic>> models, String? warning})>
  getAvailableModelsWithWarning() async {
    if (client == null) {
      return (models: <Map<String, dynamic>>[], warning: null);
    }
    final res = await client!.getAvailableModels(sessionId);
    final data = res['data'] as Map<String, dynamic>? ?? res;
    final models =
        (data['models'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final warning = data['warning']?.toString();
    return (
      models: models,
      warning: warning?.isNotEmpty == true ? warning : null,
    );
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

  Future<void> setContextWindow(int? size) async {
    if (client == null) throw StateError('Daemon non connesso');
    if (size != null && size <= 0) {
      throw ArgumentError.value(size, 'size', 'Must be positive or null');
    }
    final result = await client!.setContextWindowOverride(sessionId, size);
    final data = result['data'] as Map<String, dynamic>? ?? result;
    final hasOverride = data.containsKey('contextWindowOverride');
    final acceptedLimit = hasOverride
        ? (data['contextWindowOverride'] as num?)?.toInt()
        : size;
    final reserve = (data['compactionReservePercent'] as num?)?.toDouble();
    state = state.copyWith(
      contextWindowOverride: acceptedLimit,
      clearContextWindowOverride: acceptedLimit == null,
      compactionReservePercent: reserve,
    );
  }

  Future<void> setCompactionReservePercent(double percent) async {
    if (!percent.isFinite || percent <= 0 || percent >= 100) {
      throw ArgumentError.value(
        percent,
        'percent',
        'Must be greater than 0 and less than 100',
      );
    }
    if (client == null) throw StateError('Daemon non connesso');
    final result = await client!.setCompactionReservePercent(
      sessionId,
      percent,
    );
    final data = result['data'] as Map<String, dynamic>? ?? result;
    final reserve =
        (data['compactionReservePercent'] as num?)?.toDouble() ?? percent;
    final hasOverride = data.containsKey('contextWindowOverride');
    final acceptedLimit = hasOverride
        ? (data['contextWindowOverride'] as num?)?.toInt()
        : state.contextWindowOverride;
    state = state.copyWith(
      contextWindowOverride: acceptedLimit,
      clearContextWindowOverride: hasOverride && acceptedLimit == null,
      compactionReservePercent: reserve,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _snapSub?.cancel();
    super.dispose();
  }
}
