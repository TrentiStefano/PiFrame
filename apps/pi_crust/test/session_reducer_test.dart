import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust_protocol/pi_crust_protocol.dart';
import 'package:pi_crust/domain/session/agent_status.dart';
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/domain/session/session_reducer.dart';

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
  });
}

