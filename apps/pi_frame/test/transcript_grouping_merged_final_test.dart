// Regression: a tool-only assistant message is merged into the next assistant
// message that has text (classic one-bubble rendering). Step grouping must
// still treat that text as the turn's final answer and keep the merged tool
// calls before it. Shape taken from a real Pi session (Gemini emits
// [toolCall, empty text] messages followed by [thinking, text]).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/session/session_reducer.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/snapshot_reducer.dart';
import 'package:pi_frame/domain/session/transcript_grouping.dart';
import 'package:pi_frame/features/transcript/steps_group.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Map<String, dynamic> _user(String text) => {
  'role': 'user',
  'content': [
    {'type': 'text', 'text': text},
  ],
  'timestamp': 1000,
};

Map<String, dynamic> _toolOnly(String id, String callId, {String? thinking}) => {
  'id': id,
  'role': 'assistant',
  'content': [
    if (thinking != null) {'type': 'thinking', 'thinking': thinking},
    {
      'type': 'toolCall',
      'id': callId,
      'name': 'bash',
      'arguments': {'command': 'git status'},
    },
    {'type': 'text', 'text': ''},
  ],
  'stopReason': 'toolUse',
  'timestamp': 2000,
};

Map<String, dynamic> _result(String callId, {bool isError = false}) => {
  'role': 'toolResult',
  'toolCallId': callId,
  'toolName': 'bash',
  'content': [
    {'type': 'text', 'text': isError ? 'BLOCKED' : 'ok'},
  ],
  'isError': isError,
};

Map<String, dynamic> _final(String id, String text, {String stopReason = 'stop'}) => {
  'id': id,
  'role': 'assistant',
  'content': [
    {'type': 'thinking', 'thinking': 'Wrap up.'},
    {'type': 'text', 'text': text},
  ],
  'stopReason': stopReason,
  'timestamp': 9000,
};

List<TranscriptBlock> _group(List<SessionEntry> entries) => groupTranscript(
  entries: entries,
  mode: StepGroupingMode.withThinking,
  live: TranscriptLiveState.empty,
);

void main() {
  group('merged text-less assistant message (snapshot path)', () {
    test('final text stays outside the group and merged tools precede it', () {
      final entries = parseSessionEntries([
        _user('Check the subagents'),
        _toolOnly('a1', 'c1', thinking: 'Look at settings'),
        _result('c1'),
        _toolOnly('a2', 'c2'),
        _result('c2'),
        _final('a3', 'All subagents now use gemini.'),
      ]);

      final merged = entries.last;
      expect(merged.toolCalls.map((t) => t.toolCallId), ['c2']);
      expect(merged.toolCallsBeforeText, 1);
      expect(merged.toolCallsAfterText, isEmpty);

      final blocks = _group(entries);
      final group = blocks.whereType<StepsGroupBlock>().single;
      final finalText = blocks.whereType<FinalTextBlock>().single;
      expect(finalText.text, 'All subagents now use gemini.');
      expect(blocks.last, same(finalText));
      expect(group.steps.whereType<IntermediateTextStep>(), isEmpty);
      // Chronological order: c1, then c2 (merged into the final message).
      expect(
        group.steps.whereType<ToolStep>().map((s) => s.toolCallId),
        ['c1', 'c2'],
      );
      expect(group.hasError, isFalse);
      expect(group.failed, isFalse);
      assertTranscriptCoverage(inputEntries: entries, blocks: blocks);
    });

    test('a failed tool call does not mark a completed turn as failed', () {
      final entries = parseSessionEntries([
        _user('Commit the work'),
        _toolOnly('a1', 'c1', thinking: 'Try the commit'),
        _result('c1', isError: true),
        _toolOnly('a2', 'c2'),
        _result('c2'),
        _final('a3', 'Committed after fixing the message.'),
      ]);

      final blocks = _group(entries);
      final group = blocks.whereType<StepsGroupBlock>().single;
      expect(group.hasError, isTrue, reason: 'error icon for the failed step');
      expect(group.failed, isFalse);
      expect(group.aborted, isFalse);
      expect(blocks.whereType<FinalTextBlock>().single.text,
          'Committed after fixing the message.');
    });

    test('a turn whose last assistant message errored is failed', () {
      final entries = parseSessionEntries([
        _user('Do the release'),
        _toolOnly('a1', 'c1', thinking: 'Start'),
        _result('c1'),
        {
          'id': 'a2',
          'role': 'assistant',
          'content': [
            {'type': 'thinking', 'thinking': 'More work'},
          ],
          'stopReason': 'error',
          'errorMessage': 'Provider error',
          'timestamp': 3000,
        },
      ]);

      final group = _group(entries).whereType<StepsGroupBlock>().single;
      expect(group.failed, isTrue);
      expect(group.hasError, isTrue);
    });

    test('an empty error message at the end of a turn fails the turn', () {
      // Real Pi shape: the last message has no content, only stopReason/error.
      final entries = parseSessionEntries([
        _user('Prepare the release'),
        _toolOnly('a1', 'c1', thinking: 'Start'),
        _result('c1'),
        {
          'id': 'a2',
          'role': 'assistant',
          'content': <Map>[],
          'stopReason': 'error',
          'errorMessage': 'Provider returned 500',
          'timestamp': 3000,
        },
      ]);

      expect(entries.last.metadata?['stopReason'], 'error');
      expect(entries.last.metadata?['errorMessage'], 'Provider returned 500');
      final group = _group(entries).whereType<StepsGroupBlock>().single;
      expect(group.failed, isTrue);
    });

    test('a settled turn that stopped on a failed tool call is failed', () {
      final entries = parseSessionEntries([
        _user('Run it'),
        _toolOnly('a1', 'c1', thinking: 'Run'),
        _result('c1', isError: true),
      ]);

      final group = _group(entries).whereType<StepsGroupBlock>().single;
      expect(group.failed, isTrue);
    });

    test('an intermediate error retried successfully does not fail the turn', () {
      final entries = parseSessionEntries([
        _user('Do the release'),
        {
          'id': 'a1',
          'role': 'assistant',
          'content': [
            {'type': 'thinking', 'thinking': 'First try'},
          ],
          'stopReason': 'error',
          'timestamp': 2000,
        },
        _toolOnly('a2', 'c2'),
        _result('c2'),
        _final('a3', 'Done.'),
      ]);

      final group = _group(entries).whereType<StepsGroupBlock>().single;
      expect(group.failed, isFalse);
    });

    test('text followed by its own tool call is still intermediate', () {
      final entries = parseSessionEntries([
        _user('Explain then run'),
        {
          'id': 'a1',
          'role': 'assistant',
          'content': [
            {'type': 'thinking', 'thinking': 'Plan'},
            {'type': 'text', 'text': 'Let me run the tests.'},
            {
              'type': 'toolCall',
              'id': 'c1',
              'name': 'bash',
              'arguments': {'command': 'pnpm test'},
            },
          ],
          'stopReason': 'toolUse',
          'timestamp': 2000,
        },
        _result('c1'),
        _final('a2', 'Tests pass.'),
      ]);

      final blocks = _group(entries);
      final group = blocks.whereType<StepsGroupBlock>().single;
      expect(group.steps.whereType<IntermediateTextStep>().single.text,
          'Let me run the tests.');
      expect(blocks.whereType<FinalTextBlock>().single.text, 'Tests pass.');
    });
  });

  group('merged text-less assistant message (live path)', () {
    test('message.completed merge records tools before text', () {
      var state = const SessionState(
        sessionId: 's1',
        cwd: '/test',
        entries: [
          SessionEntry(id: 'u1', role: 'user', text: 'Check', timestamp: 1000),
        ],
      );
      var seq = 0;
      PcpEvent completed(Map<String, dynamic> message) {
        seq++;
        return MessageCompletedEvent(
          protocol: 1,
          id: 'e$seq',
          ts: 1000 + seq,
          sessionId: 's1',
          seq: seq,
          payload: {'message': message},
        );
      }

      state = reduceSessionState(state, completed(_toolOnly('a1', 'c1')));
      state = reduceSessionState(state, completed(_final('a2', 'Final answer.')));

      final last = state.entries.last;
      expect(last.text, 'Final answer.');
      expect(last.toolCallsBeforeText, 1);
      expect(last.metadata?['stopReason'], 'stop');

      final blocks = _group(state.entries);
      expect(blocks.whereType<FinalTextBlock>().single.text, 'Final answer.');
      expect(blocks.whereType<StepsGroupBlock>().single.failed, isFalse);
      expect(
        blocks.whereType<StepsGroupBlock>().single.steps.whereType<ToolStep>(),
        hasLength(1),
      );
    });
  });

  test('live empty error message fails the turn', () {
    var state = const SessionState(
      sessionId: 's1',
      cwd: '/test',
      entries: [
        SessionEntry(id: 'u1', role: 'user', text: 'Go', timestamp: 1000),
      ],
    );
    state = reduceSessionState(
      state,
      MessageCompletedEvent(
        protocol: 1,
        id: 'e1',
        ts: 1001,
        sessionId: 's1',
        seq: 1,
        payload: {'message': _toolOnly('a1', 'c1', thinking: 'Work')},
      ),
    );
    state = reduceSessionState(
      state,
      const MessageCompletedEvent(
        protocol: 1,
        id: 'e2',
        ts: 1002,
        sessionId: 's1',
        seq: 2,
        payload: {
          'message': {
            'id': 'a2',
            'role': 'assistant',
            'content': <Map>[],
            'stopReason': 'error',
            'errorMessage': 'boom',
          },
        },
      ),
    );
    expect(state.entries.last.metadata?['stopReason'], 'error');
    expect(_group(state.entries).whereType<StepsGroupBlock>().single.failed, isTrue);
  });

  group('provider error before any reply', () {
    const errorMessage = {
      'id': 'a1',
      'role': 'assistant',
      'content': <Map>[],
      'stopReason': 'error',
      'errorMessage': '429 rate limit',
    };

    test('live: marks the user message failed', () {
      var state = const SessionState(
        sessionId: 's1',
        cwd: '/test',
        entries: [
          SessionEntry(id: 'u1', role: 'user', text: 'Go', timestamp: 1000),
        ],
      );
      state = reduceSessionState(
        state,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'e1',
          ts: 1001,
          sessionId: 's1',
          seq: 1,
          payload: {'message': errorMessage},
        ),
      );
      expect(state.entries, hasLength(1));
      expect(state.entries.single.metadata?['sendError'], '429 rate limit');
    });

    test('snapshot: marks the user message failed', () {
      final entries = parseSessionEntries([_user('Go'), errorMessage]);
      expect(entries, hasLength(1));
      expect(entries.single.metadata?['sendError'], '429 rate limit');
    });

    test('aborted empty message does not mark the user message failed', () {
      final entries = parseSessionEntries([
        _user('Go'),
        {...errorMessage, 'stopReason': 'aborted'},
      ]);
      expect(entries.single.metadata?['sendError'], isNull);
    });
  });

  group('header label', () {
    Future<void> pumpHeader(WidgetTester tester, StepsGroupBlock block) {
      return tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: Scaffold(
              body: StepsGroup(
                sessionId: 's1',
                block: block,
                tokens: FrameTokens.dark,
              ),
            ),
          ),
        ),
      );
    }

    StepsGroupBlock block({
      bool hasError = false,
      bool failed = false,
      bool aborted = false,
    }) => StepsGroupBlock(
      groupId: 'steps_u1',
      turnId: 'u1',
      steps: const [],
      isRunning: false,
      hasError: hasError,
      aborted: aborted,
      failed: failed,
      stepCount: 20,
      elapsed: const Duration(seconds: 42),
    );

    testWidgets('completed turn with failed steps reads as completed', (tester) async {
      await pumpHeader(tester, block(hasError: true));
      expect(find.textContaining('Interrotto'), findsNothing);
      expect(find.textContaining('Stopped'), findsNothing);
      expect(find.byKey(const ValueKey('step_group_steps_failed_icon')), findsOneWidget);
    });

    testWidgets('failed turn reads as stopped with errors', (tester) async {
      await pumpHeader(tester, block(hasError: true, failed: true));
      expect(
        find.textContaining(RegExp('Interrotto con errori|Stopped with errors')),
        findsOneWidget,
      );
    });

    testWidgets('aborted turn reads as stopped without errors wording', (tester) async {
      await pumpHeader(tester, block(hasError: true, aborted: true));
      expect(find.textContaining(RegExp('con errori|with errors')), findsNothing);
      expect(find.textContaining(RegExp('Interrotto dopo|Stopped after')), findsOneWidget);
    });
  });
}
