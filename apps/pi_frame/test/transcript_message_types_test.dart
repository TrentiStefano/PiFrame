import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/snapshot_reducer.dart';
import 'package:pi_frame/features/tool_timeline/tool_card.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
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
