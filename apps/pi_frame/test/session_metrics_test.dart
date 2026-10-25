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
    overriddenLimit = limit;
    return {'success': true, 'contextWindowOverride': limit};
  }

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
  test(
    'session notifier exposes Pi cumulative stats without reshaping them when no override is set',
    () async {
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
      expect(notifier.state.sessionStats?['contextUsage']['percent'], closeTo(55.2, 0.1));
      expect(notifier.state.sessionStats?['contextUsage']['contextWindow'], 128000);
    },
  );

  test(
    'refreshSessionStats recalculates contextUsage using contextWindowOverride when set',
    () async {
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
      expect(notifier.state.sessionStats?['contextUsage']['contextWindow'], 100000);
      // 70,000 / 100,000 = 70.0%
      expect(notifier.state.sessionStats?['contextUsage']['percent'], 70.0);
    },
  );

  test(
    'setContextWindow calls setContextWindowOverride on client and triggers proactive compaction when tokens >= 80% threshold',
    () async {
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
      // Set override to 100k: 85,000 is 85% (>80%), so it must proactively compact
      await notifier.setContextWindow(100000);

      expect(client.overriddenLimit, 100000);
      expect(notifier.state.contextWindowOverride, 100000);
      expect(client.compactCallCount, 1);
      expect(notifier.state.sessionStats?['contextUsage']['contextWindow'], 100000);
      expect(notifier.state.sessionStats?['contextUsage']['percent'], 85.0);
    },
  );

  test(
    'sendPrompt triggers proactive compaction before prompting when tokens >= 80% of contextWindowOverride',
    () async {
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

      // Sending prompt when tokens (82k) >= 80% of override (100k)
      await notifier.sendPrompt('Analyze BlueFOX component');

      expect(client.compactCallCount, 1);
      expect(client.sentPrompts, contains('Analyze BlueFOX component'));
    },
  );
}
