import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

import '../daemon/daemon_providers.dart';
import '../daemon/pcp_client.dart';
import 'nerd_stats_settings.dart';
import 'system_metrics_model.dart';

final isWebProvider = Provider<bool>((ref) => kIsWeb);

final systemMetricsStaleDurationProvider =
    Provider<Duration>((ref) => const Duration(seconds: 5));

class SystemMetricsController extends StateNotifier<SystemMetricsData> {
  final Ref _ref;
  StreamSubscription<PcpEvent>? _eventSub;
  StreamSubscription<DaemonConnectionState>? _connSub;
  Timer? _staleTimer;
  bool _isSubscribed = false;
  PcpClient? _currentClient;

  bool get isSubscribed => _isSubscribed;

  SystemMetricsController(this._ref) : super(const SystemMetricsData.empty()) {
    _init();
  }

  void _init() {
    _ref.listen<NerdStatsSettings>(
      nerdStatsSettingsProvider,
      (prev, next) => evaluate(),
    );

    _ref.listen<PcpClient?>(
      pcpClientProvider,
      (prev, next) {
        _listenClientConnection(next);
        evaluate();
      },
    );

    _ref.listen<AsyncValue<DaemonConnectionState>>(
      connectionStateProvider,
      (prev, next) => evaluate(),
    );

    _listenClientConnection(_ref.read(pcpClientProvider));
    evaluate();
  }

  void _listenClientConnection(PcpClient? client) {
    _connSub?.cancel();
    _connSub = client?.connectionStateStream.listen((_) => evaluate());
  }

  void evaluate() {
    final settings = _ref.read(nerdStatsSettingsProvider);
    final isWeb = _ref.read(isWebProvider);
    final client = _ref.read(pcpClientProvider);
    _currentClient = client;
    final connectionAsync = _ref.read(connectionStateProvider);
    final connectionState = connectionAsync.valueOrNull ??
        client?.state ??
        DaemonConnectionState.disconnected;

    if (!settings.enabled) {
      if (_isSubscribed) {
        _unsubscribe(client);
      }
      _cancelStaleTimer();
      _cancelEventSub();
      state = const SystemMetricsData.empty();
      return;
    }

    if (isWeb) {
      if (_isSubscribed) {
        _unsubscribe(client);
      }
      _cancelStaleTimer();
      _cancelEventSub();
      state = const SystemMetricsData.empty();
      return;
    }

    final isConnected =
        connectionState == DaemonConnectionState.connected &&
        client != null &&
        client.state == DaemonConnectionState.connected;

    if (!isConnected) {
      _isSubscribed = false;
      _cancelStaleTimer();
      _cancelEventSub();
      state = state.copyWith(isStale: true);
      return;
    }

    final hasCap = client.hasCapability('system.metrics.v1');
    if (!hasCap) {
      if (_isSubscribed) {
        _unsubscribe(client);
      }
      _cancelStaleTimer();
      _cancelEventSub();
      state = const SystemMetricsData.empty(
        hasCapability: false,
        isStale: true,
      );
      return;
    }

    if (!_isSubscribed) {
      _subscribe(client);
    }
  }

  void _subscribe(PcpClient client) {
    _isSubscribed = true;
    _cancelEventSub();
    _eventSub = client.events('@daemon').listen(
      _handleEvent,
      onError: (_) {
        if (mounted) state = state.copyWith(isStale: true);
      },
    );

    client.subscribeSystemMetrics().catchError((err) {
      _isSubscribed = false;
      if (mounted) state = state.copyWith(isStale: true);
      return <String, dynamic>{};
    });
  }

  void _unsubscribe(PcpClient? client) {
    _isSubscribed = false;
    _cancelEventSub();
    _cancelStaleTimer();
    if (client != null && client.state == DaemonConnectionState.connected) {
      client.unsubscribeSystemMetrics().catchError((_) => <String, dynamic>{});
    }
  }

  void _handleEvent(PcpEvent event) {
    if (event.type != 'system.metrics') return;
    if (event is SystemMetricsEvent) {
      state = SystemMetricsData.fromEvent(event, hasCapability: true);
    } else {
      state = SystemMetricsData.fromMap(event.payload, hasCapability: true);
    }
    _resetStaleTimer();
  }

  void _resetStaleTimer() {
    _staleTimer?.cancel();
    final staleDuration = _ref.read(systemMetricsStaleDurationProvider);
    _staleTimer = Timer(staleDuration, () {
      if (mounted) {
        state = state.copyWith(isStale: true);
      }
    });
  }

  void _cancelStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  void _cancelEventSub() {
    _eventSub?.cancel();
    _eventSub = null;
  }

  @override
  void dispose() {
    _cancelStaleTimer();
    _cancelEventSub();
    _connSub?.cancel();
    if (_isSubscribed) {
      _unsubscribe(_currentClient);
    }
    super.dispose();
  }
}

final systemMetricsProvider =
    StateNotifierProvider<SystemMetricsController, SystemMetricsData>((ref) {
  return SystemMetricsController(ref);
});
