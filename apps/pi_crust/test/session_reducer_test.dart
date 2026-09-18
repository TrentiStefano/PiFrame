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
            'message': {'id': 'm1', 'role': 'assistant', 'content': 'Final content'}
          },
        ),
      );

      expect(state.entries.length, 1);
      expect(state.entries[0].text, 'Final content');
      expect(state.currentStreamingText, '');
    });

    test('ignores duplicate or older seq events', () {
      var state = const SessionState(sessionId: 's1', cwd: '/test', lastAppliedSeq: 5);

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
  });
}
