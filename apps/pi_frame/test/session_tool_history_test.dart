import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_reducer.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/snapshot_reducer.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

const _calls = [
  {
    'type': 'toolCall',
    'id': 'edit-1',
    'name': 'edit',
    'arguments': {'path': 'lib/main.dart', 'oldText': 'old', 'newText': 'new'},
  },
  {
    'type': 'toolCall',
    'id': 'write-1',
    'name': 'write',
    'arguments': {'path': 'new.txt', 'content': 'saved'},
  },
  {
    'type': 'toolCall',
    'id': 'bash-1',
    'name': 'bash',
    'arguments': {'command': 'pnpm test'},
  },
  {
    'type': 'toolCall',
    'id': 'todo-1',
    'name': 'todo',
    'arguments': {'action': 'list'},
  },
];

Map<String, dynamic> _assistant({bool thinking = true}) => {
  'id': 'assistant-1',
  'role': 'assistant',
  'content': [
    if (thinking) {'type': 'thinking', 'thinking': 'Check changes'},
    ..._calls,
  ],
};

void _expectCalls(SessionState state) {
  final calls = state.entries.expand((e) => e.toolCalls).toList();
  expect(calls.map((t) => t.toolCallId), _calls.map((t) => t['id']));
  expect(calls.map((t) => t.toolName), ['edit', 'write', 'bash', 'todo']);
  expect(calls.map((t) => t.args), _calls.map((t) => t['arguments']));
}

void main() {
  test(
    'Pi toolCall blocks survive model interruption without execution events',
    () {
      var state = reduceSessionState(
        const SessionState(sessionId: 's1', cwd: '/repo'),
        MessageCompletedEvent(
          protocol: 1,
          id: 'm1',
          ts: 1,
          sessionId: 's1',
          seq: 1,
          payload: {'message': _assistant()},
        ),
      );
      _expectCalls(state);
      state = reduceSessionState(
        state,
        const RunSettledEvent(
          protocol: 1,
          id: 'stop',
          ts: 2,
          sessionId: 's1',
          seq: 2,
          payload: {},
        ),
      );
      _expectCalls(state);
      expect(state.entries.single.thinking, 'Check changes');
      expect(state.agentStatus, AgentStatus.settled);
      expect(state.activeToolCalls, isEmpty);
    },
  );

  test('Pi tool-only assistant messages are not discarded', () {
    final state = reduceSessionState(
      const SessionState(sessionId: 's1', cwd: '/repo'),
      MessageCompletedEvent(
        protocol: 1,
        id: 'm1',
        ts: 1,
        sessionId: 's1',
        seq: 1,
        payload: {'message': _assistant(thinking: false)},
      ),
    );
    _expectCalls(state);
    expect(state.entries.single.isJunkOrInternal, isFalse);
  });

  for (final nested in [false, true]) {
    test(
      'reopen restores Pi calls, block outputs and errors (nested: $nested)',
      () {
        final messages = [
          _assistant(),
          for (final call in _calls)
            {
              'role': 'toolResult',
              'toolCallId': call['id'],
              'content': [
                {'type': 'text', 'text': '${call['name']} output'},
                {'type': 'image', 'data': 'ignored', 'mimeType': 'image/png'},
                {'type': 'text', 'text': '\nsecond block'},
              ],
              'isError': call['name'] == 'bash',
            },
        ];
        final raw = [
          for (final message in messages)
            if (nested)
              {
                'type': 'message',
                'id': 'entry-${messages.indexOf(message)}',
                'message': message,
              }
            else
              message,
        ];
        final state = applySessionSnapshot('s1', 42, {
          'session': {'cwd': '/repo'},
          'runtime': {'status': 'settled'},
          'transcript': {'entries': raw},
        });
        _expectCalls(state);
        for (final call in state.entries.single.toolCalls) {
          expect(call.output, '${call.toolName} output\nsecond block');
          expect(call.isError, call.toolName == 'bash');
          expect(call.isRunning, isFalse);
        }
        // On-demand older history uses the same parser as initial snapshots.
        expect(parseSessionEntries(raw).single.toolCalls, hasLength(4));
      },
    );
  }

  test(
    'live Pi tool completion and abort preserve args and last output once',
    () {
      var state = reduceSessionState(
        const SessionState(sessionId: 's1', cwd: '/repo'),
        MessageCompletedEvent(
          protocol: 1,
          id: 'm1',
          ts: 1,
          sessionId: 's1',
          seq: 1,
          payload: {'message': _assistant()},
        ),
      );
      state = reduceSessionState(
        state,
        const ToolStartedEvent(
          protocol: 1,
          id: 'start',
          ts: 2,
          sessionId: 's1',
          seq: 2,
          payload: {
            'toolCallId': 'bash-1',
            'toolName': 'bash',
            'args': {'command': 'pnpm test'},
          },
        ),
      );
      state = reduceSessionState(
        state,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'result',
          ts: 3,
          sessionId: 's1',
          seq: 3,
          payload: {
            'message': {
              'role': 'toolResult',
              'toolCallId': 'bash-1',
              'content': [
                {'type': 'text', 'text': 'Cancelled by user'},
              ],
              'isError': true,
            },
          },
        ),
      );
      state = reduceSessionState(
        state,
        const RunSettledEvent(
          protocol: 1,
          id: 'stop',
          ts: 4,
          sessionId: 's1',
          seq: 4,
          payload: {},
        ),
      );
      _expectCalls(state);
      final bash = state.entries.single.toolCalls.singleWhere(
        (t) => t.toolName == 'bash',
      );
      expect(bash.output, 'Cancelled by user');
      expect(bash.isError, isTrue);
      expect(bash.isRunning, isFalse);
    },
  );

  test('settling updates recorded tools without copying them to a later entry', () {
    final state = reduceSessionState(
      const SessionState(
        sessionId: 's1',
        cwd: '/repo',
        entries: [
          SessionEntry(
            id: 'first', role: 'assistant', text: 'Reading', timestamp: 1,
            toolCalls: [
              ToolExecutionState(
                toolCallId: 'read-1', toolName: 'read', args: {'path': 'a.txt'},
              ),
            ],
          ),
          SessionEntry(id: 'second', role: 'assistant', text: 'Working', timestamp: 2),
        ],
        activeToolCalls: {
          'read-1': ToolExecutionState(
            toolCallId: 'read-1', toolName: 'read', output: 'partial',
            isRunning: true, startedAt: 10,
          ),
          'write-1': ToolExecutionState(
            toolCallId: 'write-1', toolName: 'write', output: 'saved',
          ),
        },
      ),
      const RunSettledEvent(
        protocol: 1, id: 'settled', ts: 30, sessionId: 's1', seq: 1,
        payload: {},
      ),
    );
    final recorded = state.entries.first.toolCalls.single;
    expect(recorded.toolCallId, 'read-1');
    expect(recorded.args, {'path': 'a.txt'});
    expect(recorded.output, 'partial');
    expect(recorded.isRunning, isFalse);
    expect(recorded.durationMs, 20);
    expect(state.entries.last.toolCalls.single.toolCallId, 'write-1');
    expect(state.entries.expand((e) => e.toolCalls), hasLength(2));
    expect(state.activeToolCalls, isEmpty);
  });

  for (final type in ['tool_call', 'tool_use']) {
    test(
      'legacy $type calls remain supported in live and historical messages',
      () {
        final message = {
          'role': 'assistant',
          'content': [
            {
              'type': type,
              'id': 'legacy',
              'name': 'bash',
              'input': {'command': 'ls'},
            },
          ],
        };
        final state = reduceSessionState(
          const SessionState(sessionId: 's1', cwd: '/repo'),
          MessageCompletedEvent(
            protocol: 1,
            id: 'm1',
            ts: 1,
            sessionId: 's1',
            seq: 1,
            payload: {'message': message},
          ),
        );
        expect(state.entries.single.toolCalls.single.args, {'command': 'ls'});
        expect(parseSessionEntries([message]).single.toolCalls.single.args, {
          'command': 'ls',
        });
      },
    );
  }
}
