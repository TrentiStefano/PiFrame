import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_reducer.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/snapshot_reducer.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame/features/tool_timeline/tool_card.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
  home: Scaffold(body: child),
);

int _seconds(WidgetTester tester, String key) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)),
  );
  final value = texts
      .map((t) => t.data ?? '')
      .singleWhere((text) => RegExp(r'^\d+s$').hasMatch(text));
  return int.parse(value.substring(0, value.length - 1));
}

SessionState _event(
  SessionState state,
  String type,
  int ts, [
  Map<String, dynamic> payload = const {},
]) => reduceSessionState(
  state,
  PcpCodec.decodeEvent({
    'type': type,
    'ts': ts,
    'seq': state.lastAppliedSeq + 1,
    'payload': payload,
  }),
);

void main() {
  test('start times survive progress and completion freezes duration without Pi durationMs', () {
    var state = _event(
      const SessionState(sessionId: 'a', cwd: '/repo'),
      'run.started',
      1000,
    );
    expect(state.runStartedAt, 1000);
    state = _event(state, 'tool.started', 2000, {
      'toolCallId': 'cmd',
      'toolName': 'bash',
      'args': {'command': 'test'},
    });
    state = _event(state, 'tool.progress', 5000, {
      'toolCallId': 'cmd',
      'toolName': 'bash',
      'partialResult': 'working',
    });
    expect(state.activeToolCalls['cmd']!.startedAt, 2000);
    expect(state.activeToolCalls['cmd']!.elapsedMsAt(8000), 6000);
    // Duplicate starts do not replace the first observation.
    state = _event(state, 'tool.started', 8000, {
      'toolCallId': 'cmd',
      'toolName': 'bash',
    });
    expect(state.activeToolCalls['cmd']!.startedAt, 2000);
    state = _event(state, 'tool.completed', 11000, {
      'toolCallId': 'cmd',
      'toolName': 'bash',
      'result': 'done',
    });
    final tool = state.activeToolCalls['cmd']!;
    expect(tool.durationMs, 9000);
    expect(tool.elapsedMsAt(99000), 9000);
    state = _event(state, 'run.settled', 12000);
    expect(state.runStartedAt, isNull);
    expect(state.entries.single.toolCalls.single.startedAt, 2000);
    expect(state.entries.single.toolCalls.single.durationMs, 9000);
    state = _event(state, 'run.started', 20000, {'startedAt': 19000});
    expect(state.runStartedAt, 19000);
  });

  test('abort freezes running command duration, including an existing assistant call', () {
    var state = _event(
      const SessionState(sessionId: 'a', cwd: '/repo'),
      'message.completed',
      1000,
      {
        'message': {
          'role': 'assistant',
          'content': [
            {
              'type': 'toolCall',
              'id': 'cmd',
              'name': 'bash',
              'arguments': {'command': 'test'},
            },
          ],
        },
      },
    );
    state = _event(state, 'tool.started', 2000, {
      'toolCallId': 'cmd',
      'toolName': 'bash',
      'startedAt': 1500,
    });
    state = _event(state, 'run.settled', 9500);
    expect(state.entries.single.toolCalls.single.durationMs, 8000);
    expect(state.entries.single.toolCalls.single.elapsedMsAt(99999), 8000);
    expect(state.activeToolCalls, isEmpty);
  });

  test('executor duration takes priority and missing or future start times are not invented', () {
    var state = _event(
      const SessionState(sessionId: 'a', cwd: '/repo'),
      'tool.started',
      2000,
      {'toolCallId': 'cmd', 'toolName': 'bash'},
    );
    expect(state.activeToolCalls['cmd']!.elapsedMsAt(1000), 0);
    state = _event(state, 'tool.completed', 10000, {
      'toolCallId': 'cmd',
      'toolName': 'bash',
      'durationMs': 1250,
    });
    expect(state.activeToolCalls['cmd']!.durationMs, 1250);
    final legacy = applySessionSnapshot('a', 1, {
      'activeTools': [
        {'toolCallId': 'legacy', 'isRunning': true},
      ],
    });
    expect(legacy.activeToolCalls['legacy']!.elapsedMsAt(10000), isNull);
    expect(legacy.runStartedAt, isNull);
  });

  test(
    'crash and recovery freeze active timers instead of restarting them',
    () {
      var state = _event(
        const SessionState(sessionId: 'a', cwd: '/repo'),
        'run.started',
        1000,
      );
      state = _event(state, 'tool.started', 2000, {
        'toolCallId': 'cmd',
        'toolName': 'bash',
      });
      state = _event(state, 'worker.crashed', 7000);
      expect(state.runStartedAt, isNull);
      expect(state.activeToolCalls['cmd']!.isRunning, isFalse);
      expect(state.activeToolCalls['cmd']!.durationMs, 5000);
      state = _event(state, 'session.status', 15000, {'status': 'settled'});
      expect(state.activeToolCalls['cmd']!.elapsedMsAt(99999), 5000);
    },
  );

  testWidgets('completed durations survive full snapshot reconstruction', (
    tester,
  ) async {
    final state = applySessionSnapshot('a', 9, {
      'transcript': {
        'entries': [
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'toolCall',
                'id': 'cmd',
                'name': 'bash',
                'arguments': {'command': 'test'},
                'startedAt': 12000,
                'durationMs': 8000,
              },
            ],
          },
        ],
      },
    });
    final tool = state.entries.single.toolCalls.single;
    expect(tool.startedAt, 12000);
    expect(tool.durationMs, 8000);
    await tester.pumpWidget(_wrap(ToolCard(tool: tool)));
    expect(find.text('8s'), findsOneWidget);
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pumpWidget(_wrap(ToolCard(tool: tool)));
    expect(find.text('8s'), findsOneWidget);
  });

  testWidgets('running tool duration survives remount from daemon snapshot', (
    tester,
  ) async {
    final start = DateTime.now().millisecondsSinceEpoch - 12000;
    final state = applySessionSnapshot('a', 5, {
      'activeTools': [
        {
          'toolCallId': 'cmd',
          'toolName': 'bash',
          'args': {'command': 'sleep 30'},
          'isRunning': true,
          'startedAt': start,
        },
      ],
    });
    final card = ToolCard(tool: state.activeToolCalls['cmd']!);
    await tester.pumpWidget(_wrap(card));
    final before = _seconds(tester, 'tool-card-seconds-counter');
    expect(before, greaterThanOrEqualTo(12));
    await tester.pumpWidget(_wrap(const Text('Other session')));
    await tester.pumpWidget(_wrap(card));
    expect(
      _seconds(tester, 'tool-card-seconds-counter'),
      greaterThanOrEqualTo(before),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'live session timer keeps its start when switching away and back',
    (tester) async {
      final start = DateTime.now().millisecondsSinceEpoch - 18000;
      final state = applySessionSnapshot('a', 5, {
        'runtime': {'status': 'working', 'runStartedAt': start},
        'activeTools': [
          {
            'toolCallId': 'cmd',
            'toolName': 'bash',
            'args': {'command': 'sleep 30', 'timeout': 60},
            'isRunning': true,
            'startedAt': start + 6000,
          },
        ],
      });
      final container = ProviderContainer(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily('a').overrideWith(
            (ref) => SessionStateNotifier('a', null)..state = state,
          ),
          sessionStateFamily('b')
              .overrideWith((ref) => SessionStateNotifier('b', null)),
        ],
      );
      addTearDown(container.dispose);
      Future<void> show(String id) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _wrap(TranscriptView(sessionId: id)),
          ),
        );
        await tester.pump();
      }

      await show('a');
      final turnTimer = find.byKey(
        const ValueKey('livestream-seconds-counter'),
      );
      final before = _seconds(tester, 'livestream-seconds-counter');
      expect(before, greaterThanOrEqualTo(18));
      // Command deadlines do not apply to a whole multi-command agent turn.
      expect(
        find.descendant(
          of: turnTimer,
          matching: find.textContaining('timeout'),
        ),
        findsNothing,
      );
      await show('b');
      await show('a');
      expect(
        _seconds(tester, 'livestream-seconds-counter'),
        greaterThanOrEqualTo(before),
      );
      expect(
        _seconds(tester, 'tool-card-seconds-counter'),
        greaterThanOrEqualTo(12),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final (args, label) in <(Map<String, dynamic>, String?)>[
    ({'timeout': 1800}, '1800s'),
    ({'timeoutMs': 1500}, '1.5s'),
    ({'timeout_ms': 500}, '0.5s'),
    ({'timeoutSeconds': 1500}, '1500s'),
    ({'timeout_seconds': '1.5'}, '1.5s'),
    ({'timeout': '1500ms'}, '1.5s'),
    ({'WaitMsBeforeAsync': 1000}, null),
    ({'timeout': 0}, null),
    ({'timeout': -1}, null),
    ({'timeout': 'invalid 60 seconds'}, null),
    ({}, null),
  ]) {
    testWidgets('timeout uses explicit units, not magnitude: $args', (
      tester,
    ) async {
      final state = applySessionSnapshot('a', 1, {
        'activeTools': [
          {
            'toolCallId': 'cmd',
            'toolName': 'bash',
            'args': {'command': 'sleep 30', ...args},
          },
        ],
      });
      await tester.pumpWidget(
        _wrap(ToolCard(tool: state.activeToolCalls['cmd']!)),
      );
      if (label == null) {
        expect(
          find.byKey(const ValueKey('tool-card-timeout-badge')),
          findsNothing,
        );
      } else {
        expect(find.text('timeout $label'), findsOneWidget);
      }
    });
  }
}
