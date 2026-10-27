import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/session_state.dart';

class _StatsClient extends PcpClient {
  _StatsClient({this.tokens = 70656, this.contextWindow = 200000})
    : super(port: 1, token: 'test');

  final int tokens;
  final int contextWindow;
  int? overriddenLimit;
  int compactCallCount = 0;
  bool failContextSetting = false;
  List<String> sentPrompts = [];

  @override
  void attach(String sessionId, {int? lastSeq}) {}

  @override
  Future<Map<String, dynamic>> getSessionStats(String sessionId) async => {
    'data': {
      'tokens': {'total': 42000},
      'cost': 0.42,
      'contextUsage': {
        'tokens': tokens,
        'contextWindow': contextWindow,
        'percent': (tokens / contextWindow) * 100.0,
      },
    },
  };

  @override
  Future<Map<String, dynamic>> setContextWindowOverride(
    String sessionId,
    int? limit,
  ) async {
    if (failContextSetting) throw StateError('Rejected context limit');
    overriddenLimit = limit;
    return {
      'success': true,
      'contextWindowOverride': limit,
      'compactionReservePercent': 2.5,
    };
  }

  @override
  Future<Map<String, dynamic>> setCompactionReservePercent(
    String sessionId,
    double percent,
  ) async => {
    'success': true,
    'contextWindowOverride': overriddenLimit,
    'compactionReservePercent': percent,
  };

  @override
  Future<Map<String, dynamic>> compactContext(String sessionId) async {
    compactCallCount++;
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> sendPrompt(
    String sessionId,
    String text, {
    String? streamingBehavior,
    List<dynamic>? images,
  }) async {
    sentPrompts.add(text);
    return {'accepted': true};
  }
}

void main() {
  test('session notifier exposes Pi cumulative stats without reshaping them when no override is set', () async {
    final client = _StatsClient(tokens: 70656, contextWindow: 128000);
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
    expect(
      notifier.state.sessionStats?['contextUsage']['percent'],
      closeTo(55.2, 0.1),
    );
    expect(
      notifier.state.sessionStats?['contextUsage']['contextWindow'],
      128000,
    );
  });

  test('refreshSessionStats recalculates contextUsage using contextWindowOverride when set', () async {
    final client = _StatsClient(tokens: 70000, contextWindow: 200000);
    final notifier = SessionStateNotifier('session-a', client)
      ..state = const SessionState(
        sessionId: 'session-a',
        cwd: '/repo',
        currentModel: 'claude-haiku-5-5',
        contextWindowOverride: 100000,
      );
    addTearDown(() {
      notifier.dispose();
      client.dispose();
    });

    await notifier.refreshSessionStats();
    expect(
      notifier.state.sessionStats?['contextUsage']['contextWindow'],
      100000,
    );
    // 70,000 / 100,000 = 70.0%
    expect(notifier.state.sessionStats?['contextUsage']['percent'], 70.0);
  });

  test('setContextWindow updates state after backend success without local compaction', () async {
    final client = _StatsClient(tokens: 85000, contextWindow: 200000);
    final notifier = SessionStateNotifier('session-a', client)
      ..state = const SessionState(
        sessionId: 'session-a',
        cwd: '/repo',
        currentModel: 'claude-haiku-5-5',
      );
    addTearDown(() {
      notifier.dispose();
      client.dispose();
    });

    await notifier.refreshSessionStats();
    await notifier.setContextWindow(100000);

    expect(client.overriddenLimit, 100000);
    expect(notifier.state.contextWindowOverride, 100000);
    expect(client.compactCallCount, 0);
  });

  test('sendPrompt delegates compaction entirely to the backend', () async {
    final client = _StatsClient(tokens: 82000, contextWindow: 200000);
    final notifier = SessionStateNotifier('session-a', client)
      ..state = const SessionState(
        sessionId: 'session-a',
        cwd: '/repo',
        currentModel: 'claude-haiku-5-5',
        contextWindowOverride: 100000,
      );
    addTearDown(() {
      notifier.dispose();
      client.dispose();
    });

    await notifier.refreshSessionStats();
    expect(client.compactCallCount, 0);

    await notifier.sendPrompt('Analyze BlueFOX component');

    expect(client.compactCallCount, 0);
    expect(client.sentPrompts, contains('Analyze BlueFOX component'));
  });

  test(
    'failed context setting leaves state unchanged and propagates error',
    () async {
      final client = _StatsClient()..failContextSetting = true;
      final notifier = SessionStateNotifier('session-a', client)
        ..state = const SessionState(
          sessionId: 'session-a',
          cwd: '/repo',
          contextWindowOverride: 150000,
        );
      addTearDown(() {
        notifier.dispose();
        client.dispose();
      });

      await expectLater(notifier.setContextWindow(100000), throwsStateError);
      expect(notifier.state.contextWindowOverride, 150000);
    },
  );

  test('reserve percent changes only after backend success', () async {
    final client = _StatsClient();
    final notifier = SessionStateNotifier('session-a', client)
      ..state = const SessionState(sessionId: 'session-a', cwd: '/repo');
    addTearDown(() {
      notifier.dispose();
      client.dispose();
    });

    await notifier.setCompactionReservePercent(5);
    expect(notifier.state.compactionReservePercent, 5);
    expect(client.compactCallCount, 0);
  });
}
