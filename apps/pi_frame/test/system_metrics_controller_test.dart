import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/metrics/nerd_stats_settings.dart';
import 'package:pi_frame/data/metrics/system_metrics_controller.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

class _FakeMetricsPcpClient extends PcpClient {
  _FakeMetricsPcpClient({
    List<String> capabilities = const ['system.metrics.v1'],
    DaemonConnectionState initialState = DaemonConnectionState.connected,
  })  : _caps = capabilities,
        _currentState = initialState,
        super(port: 1, token: 'test');

  List<String> _caps;
  DaemonConnectionState _currentState;
  final List<PcpCommand> sentCommands = [];
  final StreamController<PcpEvent> daemonEvents =
      StreamController<PcpEvent>.broadcast();
  final StreamController<DaemonConnectionState> connStream =
      StreamController<DaemonConnectionState>.broadcast();

  @override
  DaemonConnectionState get state => _currentState;

  @override
  Stream<DaemonConnectionState> get connectionStateStream => connStream.stream;

  @override
  List<String> get capabilities => _caps;

  @override
  bool hasCapability(String cap) => _caps.contains(cap);

  void setCapabilities(List<String> caps) {
    _caps = caps;
  }

  void setConnectionState(DaemonConnectionState s) {
    _currentState = s;
    connStream.add(s);
  }

  @override
  Stream<PcpEvent> events(String sessionId) {
    if (sessionId == '@daemon') {
      return daemonEvents.stream;
    }
    return super.events(sessionId);
  }

  @override
  Future<Map<String, dynamic>> sendCommand(PcpCommand command) async {
    sentCommands.add(command);
    if (command.type == 'system.metrics.subscribe') {
      return {'intervalMs': 1000};
    }
    if (command.type == 'system.metrics.unsubscribe') {
      return {};
    }
    return {};
  }
}

void main() {
  group('SystemMetricsController', () {
    late _FakeMetricsPcpClient client;
    late ProviderContainer container;

    setUp(() {
      client = _FakeMetricsPcpClient();
      container = ProviderContainer(
        overrides: [
          pcpClientProvider.overrideWithValue(client),
          isWebProvider.overrideWithValue(false),
          systemMetricsStaleDurationProvider
              .overrideWithValue(const Duration(milliseconds: 100)),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      client.daemonEvents.close();
      client.connStream.close();
    });

    test('OFF -> no subscribe command sent', () {
      final state = container.read(systemMetricsProvider);
      expect(state.cpuPercent, isNull);
      expect(client.sentCommands, isEmpty);
    });

    test('ON -> subscribe sent once', () async {
      container.read(systemMetricsProvider);
      container.read(nerdStatsSettingsProvider.notifier).setEnabled(true);
      await Future<void>.delayed(Duration.zero);

      expect(client.sentCommands.length, 1);
      expect(
        client.sentCommands.first.type,
        'system.metrics.subscribe',
      );

      // Re-triggering evaluate while ON should not send another subscribe
      container.read(systemMetricsProvider.notifier).evaluate();
      await Future<void>.delayed(Duration.zero);
      expect(client.sentCommands.length, 1);
    });

    test('ON -> OFF -> unsubscribe sent', () async {
      container.read(systemMetricsProvider);
      container.read(nerdStatsSettingsProvider.notifier).setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(client.sentCommands.length, 1);

      container.read(nerdStatsSettingsProvider.notifier).setEnabled(false);
      await Future<void>.delayed(Duration.zero);

      expect(client.sentCommands.length, 2);
      expect(
        client.sentCommands.last.type,
        'system.metrics.unsubscribe',
      );

      final state = container.read(systemMetricsProvider);
      expect(state.cpuPercent, isNull);
    });

    test('reconnect -> re-subscribe sent', () async {
      container.read(systemMetricsProvider);
      container.read(nerdStatsSettingsProvider.notifier).setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(client.sentCommands.length, 1);

      // Simulate disconnect
      client.setConnectionState(DaemonConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);

      // Verify marked stale on disconnect
      expect(container.read(systemMetricsProvider).isStale, isTrue);

      // Simulate reconnect
      client.setConnectionState(DaemonConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      // Should have re-subscribed
      expect(client.sentCommands.length, 2);
      expect(
        client.sentCommands.last.type,
        'system.metrics.subscribe',
      );
    });

    test('capability missing -> no subscribe sent and marked no capability',
        () async {
      client.setCapabilities(['replay.v1']); // Missing system.metrics.v1
      container.read(systemMetricsProvider);
      container.read(nerdStatsSettingsProvider.notifier).setEnabled(true);
      await Future<void>.delayed(Duration.zero);

      expect(client.sentCommands, isEmpty);
      final state = container.read(systemMetricsProvider);
      expect(state.hasCapability, isFalse);
      expect(state.isStale, isTrue);
    });

    test('event -> state updated', () async {
      container.read(systemMetricsProvider);
      container.read(nerdStatsSettingsProvider.notifier).setEnabled(true);
      await Future<void>.delayed(Duration.zero);

      final event = SystemMetricsEvent(
        protocol: 1,
        id: 'evt_metrics_001',
        ts: 1726640001000,
        sessionId: '@daemon',
        seq: 1,
        payload: {
          'sampledAt': 1726640001000,
          'cpu': {'percent': 12.3},
          'memory': {
            'usedBytes': 8589934592,
            'totalBytes': 17179869184,
            'percent': 50.0,
          },
          'disk': {
            'usedBytes': 256000000000,
            'totalBytes': 512000000000,
            'percent': 50.0,
          },
          'gpu': {
            'percent': 35.5,
            'memoryUsedBytes': 4294967296,
            'memoryTotalBytes': 8589934592,
            'source': 'nvidia-smi',
          },
        },
      );

      client.daemonEvents.add(event);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(systemMetricsProvider);
      expect(state.cpuPercent, 12.3);
      expect(state.memoryPercent, 50.0);
      expect(state.memoryUsedBytes, 8589934592);
      expect(state.diskPercent, 50.0);
      expect(state.gpuPercent, 35.5);
      expect(state.gpuSource, 'nvidia-smi');
      expect(state.isStale, isFalse);
    });

    test('stale -> marked stale if no sample arrives within duration',
        () async {
      container.read(systemMetricsProvider);
      container.read(nerdStatsSettingsProvider.notifier).setEnabled(true);
      await Future<void>.delayed(Duration.zero);

      final event = SystemMetricsEvent(
        protocol: 1,
        id: 'evt_metrics_001',
        ts: 1726640001000,
        sessionId: '@daemon',
        seq: 1,
        payload: {
          'sampledAt': 1726640001000,
          'cpu': {'percent': 20.0},
        },
      );

      client.daemonEvents.add(event);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(systemMetricsProvider).isStale, isFalse);

      // Wait beyond the 100ms test stale duration
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(container.read(systemMetricsProvider).isStale, isTrue);
    });

    test('web mode -> never subscribes even when setting ON', () async {
      final webContainer = ProviderContainer(
        overrides: [
          pcpClientProvider.overrideWithValue(client),
          isWebProvider.overrideWithValue(true),
        ],
      );
      addTearDown(webContainer.dispose);

      webContainer.read(systemMetricsProvider);
      webContainer.read(nerdStatsSettingsProvider.notifier).setEnabled(true);
      await Future<void>.delayed(Duration.zero);

      expect(client.sentCommands, isEmpty);
      expect(webContainer.read(systemMetricsProvider).cpuPercent, isNull);
    });
  });
}
