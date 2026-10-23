import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/session_reducer.dart';
import 'package:pi_frame/domain/session/snapshot_reducer.dart';

void main() {
  group('SessionReducer', () {
    test('accumulates text.delta across same and different contentIndex', () {
      var state = const SessionState(sessionId: 's1', cwd: '/test');

      state = reduceSessionState(
        state,
        const TextDeltaEvent(
          protocol: 1,
          id: 'e1',
          ts: 1000,
          sessionId: 's1',
          seq: 1,
          payload: {'contentIndex': 0, 'delta': 'Hello '},
        ),
      );
      expect(state.currentStreamingText, 'Hello ');
      expect(state.agentStatus, AgentStatus.working);

      state = reduceSessionState(
        state,
        const TextDeltaEvent(
          protocol: 1,
          id: 'e2',
          ts: 1001,
          sessionId: 's1',
          seq: 2,
          payload: {'contentIndex': 0, 'delta': 'World!'},
        ),
      );
      expect(state.currentStreamingText, 'Hello World!');
    });

    test('replaces cumulative partialResult in tool.progress', () {
      var state = const SessionState(sessionId: 's1', cwd: '/test');

      state = reduceSessionState(
        state,
        const ToolProgressEvent(
          protocol: 1,
          id: 'e1',
          ts: 1000,
          sessionId: 's1',
          seq: 1,
          payload: {
            'toolCallId': 'call_1',
            'toolName': 'bash',
            'partialResult': 'First output',
          },
        ),
      );
      expect(state.toolOutputs['call_1'], 'First output');

      // Second update: must REPLACE, not concatenate
      state = reduceSessionState(
        state,
        const ToolProgressEvent(
          protocol: 1,
          id: 'e2',
          ts: 1001,
          sessionId: 's1',
          seq: 2,
          payload: {
            'toolCallId': 'call_1',
            'toolName': 'bash',
            'partialResult': 'First output and second output',
          },
        ),
      );
      expect(state.toolOutputs['call_1'], 'First output and second output');
    });

    test('message.completed commits entry and clears streaming blocks', () {
      var state = const SessionState(sessionId: 's1', cwd: '/test');

      state = reduceSessionState(
        state,
        const TextDeltaEvent(
          protocol: 1,
          id: 'e1',
          ts: 1000,
          sessionId: 's1',
          seq: 1,
          payload: {'contentIndex': 0, 'delta': 'Streaming content'},
        ),
      );
      expect(state.currentStreamingText, 'Streaming content');

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
              'id': 'm1',
              'role': 'assistant',
              'content': 'Final content',
            },
          },
        ),
      );

      expect(state.entries.length, 1);
      expect(state.entries[0].text, 'Final content');
      expect(state.currentStreamingText, '');
    });

    test('tracks extension-provided status and clears it when removed', () {
      var state = const SessionState(sessionId: 's1', cwd: '/test');
      state = reduceSessionState(
        state,
        const UiStatusEvent(
          protocol: 1,
          id: 'status-1',
          ts: 1000,
          sessionId: 's1',
          seq: 1,
          payload: {'statusKey': 'pony', 'statusText': 'Ponytail: full'},
        ),
      );
      expect(state.extensionStatuses['pony'], 'Ponytail: full');

      state = reduceSessionState(
        state,
        const UiStatusEvent(
          protocol: 1,
          id: 'status-2',
          ts: 1001,
          sessionId: 's1',
          seq: 2,
          payload: {'statusKey': 'pony', 'statusText': null},
        ),
      );
      expect(state.extensionStatuses, isEmpty);
    });

    test('ignores duplicate or older seq events', () {
      var state = const SessionState(
        sessionId: 's1',
        cwd: '/test',
        lastAppliedSeq: 5,
      );

      state = reduceSessionState(
        state,
        const TextDeltaEvent(
          protocol: 1,
          id: 'e_old',
          ts: 1000,
          sessionId: 's1',
          seq: 3,
          payload: {'contentIndex': 0, 'delta': 'Should be ignored'},
        ),
      );

      expect(state.currentStreamingText, '');
      expect(state.lastAppliedSeq, 5);
    });

    test('preserves thinking blocks and tool commands in completed assistant entry', () {
      var state = const SessionState(sessionId: 's1', cwd: '/test');

      // 1. Thinking streams
      state = reduceSessionState(
        state,
        const ThinkingDeltaEvent(
          protocol: 1,
          id: 'e1',
          ts: 1000,
          sessionId: 's1',
          seq: 1,
          payload: {'contentIndex': 0, 'delta': 'Analyzing repo architecture...'},
        ),
      );
      expect(state.currentStreamingThinking, 'Analyzing repo architecture...');

      // 2. Tool starts
      state = reduceSessionState(
        state,
        const ToolStartedEvent(
          protocol: 1,
          id: 'e2',
          ts: 1001,
          sessionId: 's1',
          seq: 2,
          payload: {
            'toolCallId': 'call_find',
            'toolName': 'find_files',
            'args': {'pattern': '*.dart'},
          },
        ),
      );
      expect(state.activeToolCalls.containsKey('call_find'), isTrue);
      expect(state.activeToolCalls['call_find']!.isRunning, isTrue);

      // 3. Tool completes
      state = reduceSessionState(
        state,
        const ToolCompletedEvent(
          protocol: 1,
          id: 'e3',
          ts: 1002,
          sessionId: 's1',
          seq: 3,
          payload: {
            'toolCallId': 'call_find',
            'toolName': 'find_files',
            'result': 'lib/main.dart\nlib/app.dart',
            'isError': false,
            'durationMs': 450,
          },
        ),
      );
      expect(state.activeToolCalls['call_find']!.isRunning, isFalse);
      expect(state.activeToolCalls['call_find']!.output, contains('lib/main.dart'));

      // 4. toolResult message completes: MUST NOT wipe active tools or thinking
      state = reduceSessionState(
        state,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'e4',
          ts: 1003,
          sessionId: 's1',
          seq: 4,
          payload: {
            'message': {
              'id': 'm_res',
              'role': 'toolResult',
              'toolCallId': 'call_find',
              'result': 'lib/main.dart\nlib/app.dart',
            },
          },
        ),
      );
      expect(state.activeToolCalls.containsKey('call_find'), isTrue);
      expect(state.currentStreamingThinking, 'Analyzing repo architecture...');

      // 5. Final text streams and completes
      state = reduceSessionState(
        state,
        const TextDeltaEvent(
          protocol: 1,
          id: 'e5',
          ts: 1004,
          sessionId: 's1',
          seq: 5,
          payload: {'contentIndex': 0, 'delta': 'Found 2 Dart files.'},
        ),
      );

      state = reduceSessionState(
        state,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'e6',
          ts: 1005,
          sessionId: 's1',
          seq: 6,
          payload: {
            'message': {
              'id': 'm_final',
              'role': 'assistant',
              'content': 'Found 2 Dart files.',
            },
          },
        ),
      );

      expect(state.entries.length, 1);
      final entry = state.entries.first;
      expect(entry.text, 'Found 2 Dart files.');
      expect(entry.thinking, 'Analyzing repo architecture...');
      expect(entry.toolCalls.length, 1);
      expect(entry.toolCalls.first.toolName, 'find_files');
      expect(entry.toolCalls.first.output, contains('lib/main.dart'));
    });

    test('RunSettledEvent saves running tool calls and thinking into entry if no message completed', () {
      var state = const SessionState(sessionId: 's1', cwd: '/test');

      state = reduceSessionState(
        state,
        const ThinkingDeltaEvent(
          protocol: 1,
          id: 'e1',
          ts: 1000,
          sessionId: 's1',
          seq: 1,
          payload: {'contentIndex': 0, 'delta': 'Thinking before settle...'},
        ),
      );

      state = reduceSessionState(
        state,
        const ToolStartedEvent(
          protocol: 1,
          id: 'e2',
          ts: 1001,
          sessionId: 's1',
          seq: 2,
          payload: {
            'toolCallId': 'call_bash',
            'toolName': 'bash',
            'args': {'command': 'ls'},
          },
        ),
      );

      state = reduceSessionState(
        state,
        const RunSettledEvent(
          protocol: 1,
          id: 'e3',
          ts: 1002,
          sessionId: 's1',
          seq: 3,
          payload: {},
        ),
      );

      expect(state.entries.length, 1);
      final entry = state.entries.first;
      expect(entry.role, 'assistant');
      expect(entry.thinking, 'Thinking before settle...');
      expect(entry.toolCalls.length, 1);
      expect(entry.toolCalls.first.toolName, 'bash');
    });

    test('internal or junk message does not wipe active tool calls or thinking', () {
      var state = const SessionState(sessionId: 's1', cwd: '/test');

      state = reduceSessionState(
        state,
        const ThinkingDeltaEvent(
          protocol: 1,
          id: 'e1',
          ts: 1000,
          sessionId: 's1',
          seq: 1,
          payload: {'contentIndex': 0, 'delta': 'Live thinking'},
        ),
      );

      state = reduceSessionState(
        state,
        const ToolStartedEvent(
          protocol: 1,
          id: 'e2',
          ts: 1001,
          sessionId: 's1',
          seq: 2,
          payload: {
            'toolCallId': 'c1',
            'toolName': 'bash',
            'args': {'command': 'git status'},
          },
        ),
      );

      // Junk / task notification arrives
      state = reduceSessionState(
        state,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'e3',
          ts: 1002,
          sessionId: 's1',
          seq: 3,
          payload: {
            'message': {
              'id': 'm_junk',
              'role': 'user',
              'content': '<task-notification>Task done</task-notification>',
            },
          },
        ),
      );

      expect(state.currentStreamingThinking, 'Live thinking');
      expect(state.activeToolCalls.containsKey('c1'), isTrue);
    });

    test('SessionReducer processes bashExecution message and sets metadata', () {
      final initial = SessionState(
        sessionId: 's1',
        cwd: '/repo',
        agentStatus: AgentStatus.settled,
        entries: const [],
        streamingTextBlocks: const {},
        streamingThinkingBlocks: const {},
        activeToolCalls: const {},
        steeringQueue: const [],
        followUpQueue: const [],
        pendingUiRequests: const [],
        usage: const {},
        lastAppliedSeq: 1,
      );

      final next = reduceSessionState(
        initial,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'e2',
          ts: 1001,
          sessionId: 's1',
          seq: 2,
          payload: {
            'message': {
              'id': 'bash_1',
              'role': 'bashExecution',
              'command': 'git status -s',
              'output': ' M lib/main.dart\n',
              'exitCode': 0,
              'cancelled': false,
              'truncated': false,
            },
          },
        ),
      );

      expect(next.entries.length, 1);
      final entry = next.entries.first;
      expect(entry.role, 'bashExecution');
      expect(entry.text, ' M lib/main.dart\n');
      expect(entry.metadata?['command'], 'git status -s');
      expect(entry.metadata?['exitCode'], 0);
      expect(entry.isJunkOrInternal, isFalse);
    });

    test('SessionReducer processes branchSummary and compactionSummary messages', () {
      final initial = SessionState(
        sessionId: 's1',
        cwd: '/repo',
        agentStatus: AgentStatus.settled,
        entries: const [],
        streamingTextBlocks: const {},
        streamingThinkingBlocks: const {},
        activeToolCalls: const {},
        steeringQueue: const [],
        followUpQueue: const [],
        pendingUiRequests: const [],
        usage: const {},
        lastAppliedSeq: 1,
      );

      final s1 = reduceSessionState(
        initial,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'e2',
          ts: 1001,
          sessionId: 's1',
          seq: 2,
          payload: {
            'message': {
              'id': 'b1',
              'role': 'branchSummary',
              'summary': 'Branch from checkpoint',
              'fromId': 'chk_99',
            },
          },
        ),
      );

      final s2 = reduceSessionState(
        s1,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'e3',
          ts: 1002,
          sessionId: 's1',
          seq: 3,
          payload: {
            'message': {
              'id': 'c1',
              'role': 'compactionSummary',
              'summary': 'Compacted conversation',
              'tokensBefore': 54000,
            },
          },
        ),
      );

      expect(s2.entries.length, 2);
      expect(s2.entries[0].role, 'branchSummary');
      expect(s2.entries[0].text, 'Branch from checkpoint');
      expect(s2.entries[0].metadata?['fromId'], 'chk_99');

      expect(s2.entries[1].role, 'compactionSummary');
      expect(s2.entries[1].text, 'Compacted conversation');
      expect(s2.entries[1].metadata?['tokensBefore'], 54000);
    });

    test('SessionReducer processes custom messages and flags display: false as internal', () {
      final initial = SessionState(
        sessionId: 's1',
        cwd: '/repo',
        agentStatus: AgentStatus.settled,
        entries: const [],
        streamingTextBlocks: const {},
        streamingThinkingBlocks: const {},
        activeToolCalls: const {},
        steeringQueue: const [],
        followUpQueue: const [],
        pendingUiRequests: const [],
        usage: const {},
        lastAppliedSeq: 1,
      );

      final sVisible = reduceSessionState(
        initial,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'e2',
          ts: 1001,
          sessionId: 's1',
          seq: 2,
          payload: {
            'message': {
              'id': 'cust_1',
              'role': 'custom',
              'customType': 'git-hook',
              'content': 'Pre-commit checks passed',
              'display': true,
            },
          },
        ),
      );

      final sHidden = reduceSessionState(
        sVisible,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'e3',
          ts: 1002,
          sessionId: 's1',
          seq: 3,
          payload: {
            'message': {
              'id': 'cust_2',
              'role': 'custom',
              'customType': 'internal-telemetry',
              'content': 'hidden telemetry',
              'display': false,
            },
          },
        ),
      );

      expect(sHidden.entries.length, 2);
      expect(sHidden.entries[0].isJunkOrInternal, isFalse);
      expect(sHidden.entries[1].isJunkOrInternal, isTrue);
    });

    test('SessionReducer toolResult updates output and isError in existing transcript entries', () {
      final entryWithRunningTool = SessionEntry(
        id: 'msg_assistant',
        role: 'assistant',
        text: 'Eseguo il test...',
        timestamp: 1000,
        toolCalls: [
          const ToolExecutionState(
            toolCallId: 't_fail',
            toolName: 'bash',
            args: {'command': 'pnpm test'},
            output: '',
            isRunning: true,
            isError: false,
          ),
        ],
      );

      final initial = SessionState(
        sessionId: 's1',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        entries: [entryWithRunningTool],
        streamingTextBlocks: const {},
        streamingThinkingBlocks: const {},
        activeToolCalls: {
          't_fail': entryWithRunningTool.toolCalls.first,
        },
        steeringQueue: const [],
        followUpQueue: const [],
        pendingUiRequests: const [],
        usage: const {},
        lastAppliedSeq: 1,
      );

      final next = reduceSessionState(
        initial,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'e2',
          ts: 1002,
          sessionId: 's1',
          seq: 2,
          payload: {
            'message': {
              'role': 'toolResult',
              'toolCallId': 't_fail',
              'result': 'FAIL test/foo.spec.ts',
              'isError': true,
            },
          },
        ),
      );

      expect(next.entries.first.toolCalls.first.isRunning, isFalse);
      expect(next.entries.first.toolCalls.first.isError, isTrue);
      expect(next.entries.first.toolCalls.first.output, 'FAIL test/foo.spec.ts');
    });

    test('ToolCompletedEvent updates output, isRunning, and isError in existing transcript entries', () {
      final initial = SessionState(
        sessionId: 's1',
        cwd: '/test',
        agentStatus: AgentStatus.working,
        entries: [
          SessionEntry(
            id: 'asst_1',
            role: 'assistant',
            text: 'I will list files.',
            toolCalls: [
              const ToolExecutionState(
                toolCallId: 'call_ls_1',
                toolName: 'ls',
                isRunning: true,
              ),
            ],
            timestamp: 1000,
          ),
        ],
        activeToolCalls: {
          'call_ls_1': const ToolExecutionState(
            toolCallId: 'call_ls_1',
            toolName: 'ls',
            isRunning: true,
          ),
        },
      );

      final next = reduceSessionState(
        initial,
        const ToolCompletedEvent(
          protocol: 1,
          id: 'evt_tc_1',
          ts: 1005,
          sessionId: 's1',
          seq: 5,
          payload: {
            'toolCallId': 'call_ls_1',
            'toolName': 'ls',
            'result': 'file1.dart\nfile2.dart',
            'isError': false,
            'durationMs': 120,
          },
        ),
      );

      expect(next.entries.first.toolCalls.first.isRunning, isFalse);
      expect(next.entries.first.toolCalls.first.isError, isFalse);
      expect(next.entries.first.toolCalls.first.output, 'file1.dart\nfile2.dart');
      expect(next.entries.first.toolCalls.first.durationMs, 120);
      expect(next.activeToolCalls['call_ls_1']?.isRunning, isFalse);
    });

    test('SessionStatusEvent settles agent status and clears streaming blocks', () {
      final initial = SessionState(
        sessionId: 's1',
        cwd: '/test',
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Incomplete streaming'},
        streamingThinkingBlocks: {0: 'Incomplete thinking'},
        activeToolCalls: {
          't1': const ToolExecutionState(
            toolCallId: 't1',
            toolName: 'bash',
            isRunning: true,
          ),
        },
      );

      final next = reduceSessionState(
        initial,
        const SessionStatusEvent(
          protocol: 1,
          id: 'evt_status_1',
          ts: 1010,
          sessionId: 's1',
          seq: 0,
          payload: {
            'status': 'settled',
            'reason': 'recovered_from_crash',
          },
        ),
      );

      expect(next.agentStatus, AgentStatus.settled);
      expect(next.streamingTextBlocks, isEmpty);
      expect(next.streamingThinkingBlocks, isEmpty);
      expect(next.activeToolCalls['t1']?.isRunning, isFalse);
    });

    test('RunEndedEvent settles status when willRetry is false and no tools are running', () {
      final initial = const SessionState(
        sessionId: 's1',
        cwd: '/test',
        agentStatus: AgentStatus.working,
      );

      final next = reduceSessionState(
        initial,
        const RunEndedEvent(
          protocol: 1,
          id: 'evt_re_1',
          ts: 1015,
          sessionId: 's1',
          seq: 6,
          payload: {'willRetry': false},
        ),
      );

      expect(next.agentStatus, AgentStatus.settled);
    });
  });

  group('applySessionSnapshot', () {
    test('restores session cost and tokens directly from payload usage', () {
      final state = applySessionSnapshot('session-cost', 10, {
        'session': {'id': 'session-cost', 'name': 'Cost Session', 'cwd': '/workspace'},
        'runtime': {'status': 'settled', 'model': 'claude-3-5-sonnet'},
        'usage': {
          'cost': 0.0845,
          'totalTokens': 15000,
          'inputTokens': 12000,
          'outputTokens': 3000,
        },
      });

      expect(state.usage?['cost'], 0.0845);
      expect(state.sessionStats?['cost'], 0.0845);
      expect(state.sessionStats?['tokens']['total'], 15000);
      expect(state.sessionStats?['tokens']['input'], 12000);
      expect(state.sessionStats?['tokens']['output'], 3000);
    });

    test('aggregates session cost and tokens from transcript entries when payload usage is empty', () {
      final state = applySessionSnapshot('session-fallback', 10, {
        'session': {'id': 'session-fallback', 'name': 'Fallback Session', 'cwd': '/workspace'},
        'runtime': {'status': 'settled', 'model': 'claude-3-5-sonnet'},
        'usage': {},
        'transcript': {
          'entries': [
            {
              'id': 'msg-1',
              'role': 'assistant',
              'content': 'First step',
              'usage': {
                'cost': {'total': 0.025},
                'tokens': {'total': 5000, 'input': 4000, 'output': 1000},
              },
            },
            {
              'id': 'msg-2',
              'role': 'assistant',
              'content': 'Second step',
              'usage': {
                'cost': 0.035,
                'tokens': {'total': 12000, 'input': 9000, 'output': 3000},
              },
            },
          ],
        },
      });

      // Total cost should be 0.025 + 0.035 = 0.060
      expect(state.usage?['cost'], closeTo(0.060, 0.0001));
      expect(state.sessionStats?['cost'], closeTo(0.060, 0.0001));
      expect(state.sessionStats?['tokens']['total'], 12000);
    });
  });
}

