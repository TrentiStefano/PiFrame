import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final connectionStateProvider = StreamProvider<DaemonConnectionState>((ref) {
  final client = ref.watch(pcpClientProvider);
  if (client == null) return Stream.value(DaemonConnectionState.disconnected);
  return client.connectionStateStream;
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

  final res = await client.listSessions();
  final data = res['data'] as Map<String, dynamic>?;
  final sessions = data?['sessions'] as List?;
  return sessions?.cast<Map<String, dynamic>>() ?? [];
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
      state = applySessionSnapshot(sessionId, snapshot.seq, snapshot.payload);
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
    unawaited(refreshDefaults());
  }

  bool _defaultsLoading = false;

  Future<void> refreshDefaults() async {
    if (client == null || state.readOnly || _defaultsLoading) return;
    final needsModel = state.currentModel == null || state.currentModel!.isEmpty;
    final needsThinking = state.currentThinkingLevel == null || state.currentThinkingLevel!.isEmpty;
    if (!needsModel && !needsThinking) return;

    _defaultsLoading = true;
    try {
      String? resolvedModel;
      String? resolvedThinking;

      if (needsModel) {
        final res = await client!.getAvailableModels(sessionId);
        final data = res['data'] as Map<String, dynamic>? ?? res;
        final currentModelRaw = data['currentModel'] ?? data['model'];
        if (currentModelRaw is Map) {
          resolvedModel = (currentModelRaw['name'] ?? currentModelRaw['id'])?.toString();
        } else if (currentModelRaw is String && currentModelRaw.isNotEmpty) {
          resolvedModel = currentModelRaw;
        }

        if (resolvedModel == null || resolvedModel.isEmpty) {
          final models = (data['models'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          final defaultModel = models.firstWhere(
            (m) => m['isDefault'] == true || m['default'] == true,
            orElse: () => models.isNotEmpty ? models.first : const {},
          );
          if (defaultModel.isNotEmpty) {
            resolvedModel = (defaultModel['name'] ?? defaultModel['id'])?.toString();
          }
        }

        if (needsThinking && data['currentThinkingLevel'] != null) {
          resolvedThinking = data['currentThinkingLevel'].toString();
        }
      }

      if (needsThinking && (resolvedThinking == null || resolvedThinking.isEmpty)) {
        final tRes = await client!.getAvailableThinkingLevels(sessionId);
        final tData = tRes['data'] as Map<String, dynamic>? ?? tRes;
        final levelRaw = tData['currentLevel'] ?? tData['thinkingLevel'] ?? tData['defaultLevel'];
        if (levelRaw != null) {
          resolvedThinking = levelRaw.toString();
        } else {
          final levels = (tData['levels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
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
        state = state.copyWith(sessionStats: Map<String, dynamic>.from(data));
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

  Future<void> sendPrompt(String text, {String? streamingBehavior}) async {
    if (client == null) throw StateError('Daemon non connesso');
    await client!.sendPrompt(
      sessionId,
      text,
      streamingBehavior: streamingBehavior,
    );
  }

  Future<Map<String, dynamic>?> interrupt() async {
    if (client == null) return null;
    return client!.interruptAgent(sessionId);
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
    final model = result['data'] as Map<String, dynamic>?;
    state = state.copyWith(
      currentModel: (model?['name'] ?? model?['id'] ?? modelId).toString(),
    );
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

  Future<void> setContextWindow(int? size) async {
    Map<String, dynamic>? updatedStats;
    if (state.sessionStats != null) {
      updatedStats = Map<String, dynamic>.from(state.sessionStats!);
      final cu = updatedStats['contextUsage'] as Map?;
      final tokens = (cu?['tokens'] as num?)?.toDouble() ??
          (state.usage?['totalTokens'] as num?)?.toDouble() ??
          0.0;
      final win = size ?? (cu?['contextWindow'] as num?)?.toInt();
      if (win != null && win > 0) {
        final pct = (tokens / win) * 100.0;
        updatedStats['contextUsage'] = {
          if (cu != null) ...Map<String, dynamic>.from(cu),
          'contextWindow': win,
          'percent': pct,
          'tokens': tokens.toInt(),
        };
      }
    }
    state = state.copyWith(
      contextWindowOverride: size,
      sessionStats: updatedStats ?? state.sessionStats,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _snapSub?.cancel();
    super.dispose();
  }
}
