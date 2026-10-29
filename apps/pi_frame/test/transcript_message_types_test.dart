import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_reducer.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/snapshot_reducer.dart';
import 'package:pi_frame/features/tool_timeline/tool_card.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

void main() {
  testWidgets('live tool calls appear once and retain their execution state', (tester) async {
    final notifier = SessionStateNotifier('live-tools', null)
      ..state = const SessionState(sessionId: 'live-tools', cwd: '/repo');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        sessionStateFamily('live-tools').overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(body: TranscriptView(sessionId: 'live-tools')),
      ),
    ));

    Future<void> apply(PcpEvent event) async {
      notifier.state = reduceSessionState(notifier.state, event);
      await tester.pump();
    }

    await apply(const RunStartedEvent(protocol: 1, id: 'run', ts: 1,
        sessionId: 'live-tools', seq: 1, payload: {}));
    await apply(const MessageCompletedEvent(protocol: 1, id: 'message', ts: 2,
        sessionId: 'live-tools', seq: 2, payload: {
      'message': {'id': 'assistant-1', 'role': 'assistant', 'content': [
        {'type': 'text', 'text': 'Reading files'},
        {'type': 'toolCall', 'id': 'read-1', 'name': 'read', 'arguments': {'path': 'a.txt'}},
      ]},
    }));
    await apply(const ToolStartedEvent(protocol: 1, id: 'start', ts: 3,
        sessionId: 'live-tools', seq: 3, payload: {
      'toolCallId': 'read-1', 'toolName': 'read', 'args': {'path': 'a.txt'},
    }));
    var cards = tester.widgetList<ToolCard>(find.byType(ToolCard)).toList();
    expect(cards, hasLength(1));
    expect(cards.single.tool.isRunning, isTrue);
    expect(cards.single.tool.startedAt, 3);

    await apply(const ToolProgressEvent(protocol: 1, id: 'progress', ts: 4,
        sessionId: 'live-tools', seq: 4, payload: {
      'toolCallId': 'read-1', 'toolName': 'read', 'partialResult': 'partial',
    }));
    cards = tester.widgetList<ToolCard>(find.byType(ToolCard)).toList();
    expect(cards, hasLength(1));
    expect(cards.single.tool.output, 'partial');

    await apply(const ToolCompletedEvent(protocol: 1, id: 'end', ts: 5,
        sessionId: 'live-tools', seq: 5, payload: {
      'toolCallId': 'read-1', 'toolName': 'read', 'result': 'finished',
      'isError': false, 'durationMs': 2,
    }));
    await apply(const MessageCompletedEvent(protocol: 1, id: 'answer', ts: 6,
        sessionId: 'live-tools', seq: 6, payload: {
      'message': {'id': 'assistant-2', 'role': 'assistant', 'content': 'Done'},
    }));
    cards = tester.widgetList<ToolCard>(find.byType(ToolCard)).toList();
    expect(cards, hasLength(1));
    expect(cards.single.tool.isRunning, isFalse);
    expect(cards.single.tool.output, 'finished');
    expect(notifier.state.entries.expand((e) => e.toolCalls), hasLength(1));
    await apply(const RunSettledEvent(protocol: 1, id: 'settled', ts: 7,
        sessionId: 'live-tools', seq: 7, payload: {}));
    expect(tester.widgetList<ToolCard>(find.byType(ToolCard)), hasLength(1));
  });

  testWidgets('snapshot merges matching active tools without hiding other calls', (tester) async {
    final notifier = SessionStateNotifier('snapshot-tools', null)
      ..state = applySessionSnapshot('snapshot-tools', 10, {
        'session': {'cwd': '/repo'},
        'transcript': {'entries': [
          {'id': 'assistant-1', 'role': 'assistant', 'content': [
            {'type': 'toolCall', 'id': 'read-1', 'name': 'read', 'arguments': {'path': 'a.txt'}},
            {'type': 'toolCall', 'name': 'edit', 'arguments': {'path': 'c.txt'}},
          ]},
        ]},
        'activeTools': [
          {'toolCallId': 'read-1', 'toolName': 'read', 'args': {'path': 'a.txt'}, 'isRunning': true, 'output': 'partial'},
          {'toolCallId': 'read-2', 'toolName': 'read', 'args': {'path': 'b.txt'}, 'isRunning': true},
          {'toolName': 'write', 'args': {'path': 'd.txt'}, 'isRunning': true},
        ],
      });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        sessionStateFamily('snapshot-tools').overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(body: TranscriptView(sessionId: 'snapshot-tools')),
      ),
    ));
    await tester.pump();
    final cards = tester.widgetList<ToolCard>(find.byType(ToolCard)).toList();
    expect(cards, hasLength(4));
    expect(cards.map((c) => c.tool.toolCallId), containsAll(['read-1', 'read-2']));
    expect(cards.where((c) => c.tool.toolCallId.isEmpty), hasLength(2));
    final matched = cards.singleWhere((c) => c.tool.toolCallId == 'read-1').tool;
    expect(matched.isRunning, isTrue);
    expect(matched.output, 'partial');
  });

  testWidgets('reopened Pi actions stay visible with command and stored output', (tester) async {
    final notifier = SessionStateNotifier('history', null)
      ..state = applySessionSnapshot('history', 10, {
        'session': {'cwd': '/repo'},
        'transcript': {'entries': [
          {'id': 'assistant-1', 'role': 'assistant', 'content': [
            for (final name in ['edit', 'write', 'bash', 'todo'])
              {'type': 'toolCall', 'id': name, 'name': name,
                'arguments': {'command': 'git status', 'path': 'lib/main.dart'}},
          ]},
          {'role': 'toolResult', 'toolCallId': 'bash', 'content': [
            {'type': 'text', 'text': 'On branch main'},
          ]},
        ]},
      });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        sessionStateFamily('history').overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(body: TranscriptView(sessionId: 'history')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ToolCard), findsNWidgets(4));
    for (final name in ['edit', 'write', 'bash', 'todo']) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.tap(find.text('bash'));
    await tester.pumpAndSettle();
    expect(find.textContaining('On branch main'), findsOneWidget);
    expect(find.textContaining('git status'), findsWidgets);
  });

  testWidgets('renders bashExecution, branchSummary, compactionSummary, and custom messages', (
    tester,
  ) async {
    final notifier = SessionStateNotifier('session_types', null)
      ..state = SessionState(
        sessionId: 'session_types',
        sessionName: 'Message Types Test',
        cwd: '/test/repo',
        entries: [
          SessionEntry(
            id: 'bash_1',
            role: 'bashExecution',
            text: 'On branch main\nnothing to commit, working tree clean',
            timestamp: 100,
            metadata: {
              'command': 'git status',
              'exitCode': 0,
              'cancelled': false,
              'truncated': false,
            },
          ),
          SessionEntry(
            id: 'branch_1',
            role: 'branchSummary',
            text: 'Branched from entry entry_01',
            timestamp: 200,
            metadata: {
              'fromId': 'entry_01',
            },
          ),
          SessionEntry(
            id: 'compaction_1',
            role: 'compactionSummary',
            text: 'Compacted context',
            timestamp: 300,
            metadata: {
              'tokensBefore': 32000,
            },
          ),
          SessionEntry(
            id: 'custom_1',
            role: 'custom',
            text: 'Custom extension notice',
            timestamp: 400,
            metadata: {
              'customType': 'linter-hook',
              'display': true,
            },
          ),
        ],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily('session_types').overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: TranscriptView(sessionId: 'session_types')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify bash execution card
    expect(find.text('git status'), findsOneWidget);
    expect(find.text('exit 0'), findsOneWidget);
    expect(find.textContaining('On branch main'), findsOneWidget);

    // Verify branch summary banner
    expect(find.text('Branched from entry entry_01'), findsOneWidget);
    expect(find.text('orig: entry_01'), findsOneWidget);

    // Verify compaction summary banner
    expect(find.text('Compacted context'), findsOneWidget);
    expect(find.text('32000 token iniziali'), findsOneWidget);

    // Verify custom extension card
    expect(find.text('linter-hook'), findsOneWidget);
    expect(find.text('Custom extension notice'), findsOneWidget);
  });
}
