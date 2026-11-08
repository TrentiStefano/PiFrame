import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/transcript/step_grouping_settings.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_reducer.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/transcript_grouping.dart';
import 'package:pi_frame/features/transcript/step_group_expansion.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

void main() {
  group('transcript_grouping - core grouping logic', () {
    test('alternating thinking & tool calls grouped in order, final text outside', () {
      final entries = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Find the bug and fix it',
          timestamp: 1000,
        ),
        const SessionEntry(
          id: 'asst1',
          role: 'assistant',
          text: '',
          thinking: 'Let me grep for the symbol',
          toolCalls: [
            ToolExecutionState(
              toolCallId: 't1',
              toolName: 'grep',
              args: {'pattern': 'error'},
              output: 'found 2 lines',
              startedAt: 1200,
              durationMs: 300,
            ),
          ],
          timestamp: 1500,
        ),
        const SessionEntry(
          id: 'asst2',
          role: 'assistant',
          text: '',
          thinking: 'Now let me read the file',
          toolCalls: [
            ToolExecutionState(
              toolCallId: 't2',
              toolName: 'read_file',
              args: {'path': 'lib/a.dart'},
              output: 'content here',
              startedAt: 1600,
              durationMs: 400,
            ),
          ],
          timestamp: 2000,
        ),
        const SessionEntry(
          id: 'asst3',
          role: 'assistant',
          text: 'I found and fixed the bug.',
          thinking: 'Ready to write final response',
          toolCalls: [],
          timestamp: 2500,
        ),
      ];

      final blocks = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );

      expect(blocks.length, 3);
      expect(blocks[0], isA<EntryBlock>());
      expect((blocks[0] as EntryBlock).entry.id, 'u1');

      expect(blocks[1], isA<StepsGroupBlock>());
      final group = blocks[1] as StepsGroupBlock;
      expect(group.groupId, 'steps_u1');
      expect(group.turnId, 'u1');
      expect(group.isRunning, isFalse);
      expect(group.hasError, isFalse);
      expect(group.aborted, isFalse);
      expect(group.stepCount, 5); // 3 thinking + 2 tools
      expect(group.steps.length, 5);
      expect(group.elapsed, const Duration(milliseconds: 1500)); // 2500 - 1000

      // Order check: thinking1, tool1, thinking2, tool2, thinking3
      expect(group.steps[0], isA<ThinkingStep>());
      expect((group.steps[0] as ThinkingStep).text, 'Let me grep for the symbol');

      expect(group.steps[1], isA<ToolStep>());
      expect((group.steps[1] as ToolStep).toolName, 'grep');

      expect(group.steps[2], isA<ThinkingStep>());
      expect((group.steps[2] as ThinkingStep).text, 'Now let me read the file');

      expect(group.steps[3], isA<ToolStep>());
      expect((group.steps[3] as ToolStep).toolName, 'read_file');

      expect(group.steps[4], isA<ThinkingStep>());
      expect((group.steps[4] as ThinkingStep).text, 'Ready to write final response');

      expect(group.latestStep, group.steps[4]);

      // Final text block
      expect(blocks[2], isA<FinalTextBlock>());
      final finalBlock = blocks[2] as FinalTextBlock;
      expect(finalBlock.text, 'I found and fixed the bug.');
      expect(finalBlock.turnId, 'u1');
      expect(finalBlock.entry.id, 'asst3');
      expect(finalBlock.entry.thinking, isNull);
      expect(finalBlock.entry.toolCalls, isEmpty);

      // NO LOSS assertion
      assertTranscriptCoverage(inputEntries: entries, blocks: blocks);
    });

    test('withThinking does not group a tool-only turn while always does', () {
      final entries = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Run the tool',
          timestamp: 1000,
        ),
        const SessionEntry(
          id: 'asst1',
          role: 'assistant',
          text: 'Running tool now...',
          thinking: null,
          toolCalls: [
            ToolExecutionState(
              toolCallId: 't1',
              toolName: 'calculator',
              args: {'expr': '2+2'},
              output: '4',
            ),
          ],
          timestamp: 1500,
        ),
        const SessionEntry(
          id: 'asst2',
          role: 'assistant',
          text: 'The answer is 4.',
          thinking: null,
          toolCalls: [],
          timestamp: 2000,
        ),
      ];

      // withThinking: tool-only turn has no thinking -> NOT grouped
      final blocksWithThinking = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );

      expect(blocksWithThinking.length, 3);
      expect(blocksWithThinking.every((b) => b is EntryBlock), isTrue);
      assertTranscriptCoverage(inputEntries: entries, blocks: blocksWithThinking);

      // always: has tool call -> grouped!
      final blocksAlways = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.always,
        live: TranscriptLiveState.empty,
      );

      expect(blocksAlways.length, 3);
      expect(blocksAlways[0], isA<EntryBlock>());
      expect(blocksAlways[1], isA<StepsGroupBlock>());
      expect(blocksAlways[2], isA<FinalTextBlock>());

      final group = blocksAlways[1] as StepsGroupBlock;
      expect(group.steps.length, 2);
      expect(group.steps[0], isA<IntermediateTextStep>());
      expect((group.steps[0] as IntermediateTextStep).text, 'Running tool now...');
      expect(group.steps[1], isA<ToolStep>());
      expect((group.steps[1] as ToolStep).toolName, 'calculator');
      expect(group.stepCount, 1); // 1 tool step

      final finalBlock = blocksAlways[2] as FinalTextBlock;
      expect(finalBlock.text, 'The answer is 4.');
      assertTranscriptCoverage(inputEntries: entries, blocks: blocksAlways);
    });

    test('off returns entries unchanged with LiveTailBlock marker when streaming', () {
      final entries = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Hello',
          timestamp: 1000,
        ),
        const SessionEntry(
          id: 'asst1',
          role: 'assistant',
          text: 'Hi there',
          thinking: 'thought',
          timestamp: 1500,
        ),
      ];

      const live = TranscriptLiveState(
        isRunning: true,
        streamingText: ' streaming...',
      );

      final blocks = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.off,
        live: live,
      );

      expect(blocks.length, 3);
      expect(blocks[0], isA<EntryBlock>());
      expect((blocks[0] as EntryBlock).entry.id, 'u1');
      expect(blocks[1], isA<EntryBlock>());
      expect((blocks[1] as EntryBlock).entry.id, 'asst1');

      // Live stream marker
      expect(blocks[2], isA<LiveTailBlock>());
      final liveTail = blocks[2] as LiveTailBlock;
      expect(liveTail.text, ' streaming...');
      expect(liveTail.isRunning, isTrue);
      expect(liveTail.turnId, 'u1');
    });

    test('streaming: running turn with live thinking + active tool -> isRunning, latestStep = active tool', () {
      final entries = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Do some work',
          timestamp: 1000,
        ),
      ];

      const live = TranscriptLiveState(
        isRunning: true,
        streamingThinking: 'Pondering strategy...',
        activeToolCalls: [
          ToolExecutionState(
            toolCallId: 't_active',
            toolName: 'web_search',
            isRunning: true,
            startedAt: 1200,
          ),
        ],
      );

      final blocks = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.withThinking,
        live: live,
      );

      expect(blocks.length, 2);
      expect(blocks[0], isA<EntryBlock>());

      expect(blocks[1], isA<StepsGroupBlock>());
      final group = blocks[1] as StepsGroupBlock;
      expect(group.isRunning, isTrue);
      expect(group.turnId, 'u1');
      expect(group.steps.length, 2);

      expect(group.steps[0], isA<ThinkingStep>());
      final thinking = group.steps[0] as ThinkingStep;
      expect(thinking.id, 'live_u1_thinking');
      expect(thinking.text, 'Pondering strategy...');
      expect(thinking.isStreaming, isTrue);

      expect(group.steps[1], isA<ToolStep>());
      final tool = group.steps[1] as ToolStep;
      expect(tool.id, 't_active');
      expect(tool.toolName, 'web_search');
      expect(tool.isRunning, isTrue);

      expect(group.latestStep, group.steps[1]);
      expect(group.stepCount, 2);
    });

    test('trailing streaming text is LiveTail candidate then becomes intermediate when a tool call is added', () {
      final entries = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Explain and test',
          timestamp: 1000,
        ),
        const SessionEntry(
          id: 'asst1',
          role: 'assistant',
          text: '',
          thinking: 'Initial plan',
          timestamp: 1200,
        ),
      ];

      // Phase 1: Live text streaming with no subsequent tool call -> candidate final in LiveTailBlock
      const liveCandidate = TranscriptLiveState(
        isRunning: true,
        streamingText: 'Here is what I plan to do...',
      );

      final blocksPhase1 = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.withThinking,
        live: liveCandidate,
      );

      expect(blocksPhase1.length, 3);
      expect(blocksPhase1[0], isA<EntryBlock>());
      expect(blocksPhase1[1], isA<StepsGroupBlock>());
      final groupPhase1 = blocksPhase1[1] as StepsGroupBlock;
      expect(groupPhase1.steps.length, 1);
      expect(groupPhase1.steps[0], isA<ThinkingStep>());

      expect(blocksPhase1[2], isA<LiveTailBlock>());
      final liveTail1 = blocksPhase1[2] as LiveTailBlock;
      expect(liveTail1.text, 'Here is what I plan to do...');

      // Phase 2: A tool call is now added after the streaming text!
      const liveWithTool = TranscriptLiveState(
        isRunning: true,
        streamingText: 'Here is what I plan to do...',
        activeToolCalls: [
          ToolExecutionState(
            toolCallId: 't_exec',
            toolName: 'run_tests',
            isRunning: true,
          ),
        ],
      );

      final blocksPhase2 = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.withThinking,
        live: liveWithTool,
      );

      // Live text now converted to IntermediateTextStep inside the group!
      expect(blocksPhase2.length, 2);
      expect(blocksPhase2[0], isA<EntryBlock>());
      expect(blocksPhase2[1], isA<StepsGroupBlock>());

      final groupPhase2 = blocksPhase2[1] as StepsGroupBlock;
      expect(groupPhase2.steps.length, 3);
      expect(groupPhase2.steps[0], isA<ThinkingStep>());
      expect(groupPhase2.steps[1], isA<IntermediateTextStep>());
      expect(
        (groupPhase2.steps[1] as IntermediateTextStep).text,
        'Here is what I plan to do...',
      );
      expect(groupPhase2.steps[2], isA<ToolStep>());
      expect((groupPhase2.steps[2] as ToolStep).toolName, 'run_tests');
    });

    test('error turn -> hasError and aborted -> aborted & hasError', () {
      // Tool error
      final entriesToolError = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Test error',
          timestamp: 1000,
        ),
        const SessionEntry(
          id: 'asst1',
          role: 'assistant',
          text: '',
          thinking: 'thought',
          toolCalls: [
            ToolExecutionState(
              toolCallId: 't1',
              toolName: 'bad_cmd',
              isError: true,
              output: 'command not found',
            ),
          ],
          timestamp: 1500,
        ),
      ];

      final blocksToolError = groupTranscript(
        entries: entriesToolError,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );

      final groupToolError = blocksToolError.whereType<StepsGroupBlock>().first;
      expect(groupToolError.hasError, isTrue);
      expect(groupToolError.aborted, isFalse);
      assertTranscriptCoverage(
        inputEntries: entriesToolError,
        blocks: blocksToolError,
      );

      // Aborted turn via metadata
      final entriesAborted = [
        const SessionEntry(
          id: 'u2',
          role: 'user',
          text: 'Cancel this',
          timestamp: 1000,
        ),
        const SessionEntry(
          id: 'asst2',
          role: 'assistant',
          text: 'Stopped here',
          thinking: 'Interrupted thought',
          timestamp: 1500,
          metadata: {'stopReason': 'aborted'},
        ),
      ];

      final blocksAborted = groupTranscript(
        entries: entriesAborted,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );

      final groupAborted = blocksAborted.whereType<StepsGroupBlock>().first;
      expect(groupAborted.aborted, isTrue);
      expect(groupAborted.hasError, isTrue);
      assertTranscriptCoverage(
        inputEntries: entriesAborted,
        blocks: blocksAborted,
      );
    });

    test('multiple turns partitioned and grouped independently', () {
      final entries = [
        // Turn 1
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'First question',
          timestamp: 1000,
        ),
        const SessionEntry(
          id: 'asst1',
          role: 'assistant',
          text: 'First answer',
          thinking: 'Thinking turn 1',
          timestamp: 1500,
        ),
        // Turn 2
        const SessionEntry(
          id: 'u2',
          role: 'user',
          text: 'Second question',
          timestamp: 2000,
        ),
        const SessionEntry(
          id: 'asst2',
          role: 'assistant',
          text: 'Second answer',
          thinking: 'Thinking turn 2',
          timestamp: 2500,
        ),
      ];

      final blocks = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );

      expect(blocks.length, 6);
      expect(blocks[0], isA<EntryBlock>());
      expect((blocks[0] as EntryBlock).entry.id, 'u1');

      expect(blocks[1], isA<StepsGroupBlock>());
      final g1 = blocks[1] as StepsGroupBlock;
      expect(g1.groupId, 'steps_u1');
      expect(g1.turnId, 'u1');

      expect(blocks[2], isA<FinalTextBlock>());
      expect((blocks[2] as FinalTextBlock).text, 'First answer');

      expect(blocks[3], isA<EntryBlock>());
      expect((blocks[3] as EntryBlock).entry.id, 'u2');

      expect(blocks[4], isA<StepsGroupBlock>());
      final g2 = blocks[4] as StepsGroupBlock;
      expect(g2.groupId, 'steps_u2');
      expect(g2.turnId, 'u2');

      expect(blocks[5], isA<FinalTextBlock>());
      expect((blocks[5] as FinalTextBlock).text, 'Second answer');

      assertTranscriptCoverage(inputEntries: entries, blocks: blocks);
    });

    test('milestones not swallowed and ordering remains stable', () {
      final entries = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Do complex task',
          timestamp: 1000,
        ),
        const SessionEntry(
          id: 'asst1',
          role: 'assistant',
          text: '',
          thinking: 'Step 1 thought',
          toolCalls: [
            ToolExecutionState(toolCallId: 't1', toolName: 'build'),
          ],
          timestamp: 1200,
        ),
        const SessionEntry(
          id: 'comp1',
          role: 'compactionSummary',
          text: 'Compacted context',
          timestamp: 1300,
        ),
        const SessionEntry(
          id: 'asst2',
          role: 'assistant',
          text: '',
          thinking: 'Step 2 thought',
          toolCalls: [
            ToolExecutionState(toolCallId: 't2', toolName: 'deploy'),
          ],
          timestamp: 1400,
        ),
        const SessionEntry(
          id: 'bash1',
          role: 'bashExecution',
          text: 'deployment status ok',
          timestamp: 1500,
        ),
        const SessionEntry(
          id: 'asst3',
          role: 'assistant',
          text: 'Everything completed successfully.',
          timestamp: 1600,
        ),
      ];

      final blocks = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );

      // Verify milestones are present as EntryBlocks in stable order
      final compactionBlock = blocks
          .whereType<EntryBlock>()
          .firstWhere((b) => b.entry.id == 'comp1');
      expect(compactionBlock.entry.role, 'compactionSummary');

      final bashBlock = blocks
          .whereType<EntryBlock>()
          .firstWhere((b) => b.entry.id == 'bash1');
      expect(bashBlock.entry.role, 'bashExecution');

      final finalBlock = blocks.whereType<FinalTextBlock>().first;
      expect(finalBlock.text, 'Everything completed successfully.');

      final group = blocks.whereType<StepsGroupBlock>().first;
      expect(group.steps.length, 4); // thinking1, tool1, thinking2, tool2

      // Verify ordering: u1 -> group -> comp1 -> bash1 -> finalBlock
      expect((blocks[0] as EntryBlock).entry.id, 'u1');
      expect(blocks[1], group);
      expect((blocks[2] as EntryBlock).entry.id, 'comp1');
      expect((blocks[3] as EntryBlock).entry.id, 'bash1');
      expect(blocks[4], finalBlock);

      assertTranscriptCoverage(inputEntries: entries, blocks: blocks);
    });

    test('stable step ids between two computations as streaming grows', () {
      final entries = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Compile app',
          timestamp: 1000,
        ),
      ];

      // Streaming state at time T1
      const liveT1 = TranscriptLiveState(
        isRunning: true,
        streamingThinking: 'Compiling...',
      );

      final blocksT1 = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.withThinking,
        live: liveT1,
      );
      final groupT1 = blocksT1.whereType<StepsGroupBlock>().first;
      final thinkingT1 = groupT1.steps[0] as ThinkingStep;
      expect(thinkingT1.id, 'live_u1_thinking');

      // Streaming state at time T2: thinking expanded, tool starts
      const liveT2 = TranscriptLiveState(
        isRunning: true,
        streamingThinking: 'Compiling... optimizing bytecode',
        activeToolCalls: [
          ToolExecutionState(
            toolCallId: 'compile_call_99',
            toolName: 'dart_compile',
            isRunning: true,
          ),
        ],
      );

      final blocksT2 = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.withThinking,
        live: liveT2,
      );
      final groupT2 = blocksT2.whereType<StepsGroupBlock>().first;
      final thinkingT2 = groupT2.steps[0] as ThinkingStep;
      final toolT2 = groupT2.steps[1] as ToolStep;

      // Stable IDs
      expect(thinkingT2.id, 'live_u1_thinking');
      expect(thinkingT2.id, thinkingT1.id);
      expect(toolT2.id, 'compile_call_99');

      // T3: tool committed to an assistant entry
      final entriesT3 = [
        ...entries,
        const SessionEntry(
          id: 'asst_committed',
          role: 'assistant',
          text: '',
          thinking: 'Compiling... optimizing bytecode',
          toolCalls: [
            ToolExecutionState(
              toolCallId: 'compile_call_99',
              toolName: 'dart_compile',
              output: 'Compilation succeeded',
              isRunning: false,
            ),
          ],
          timestamp: 1500,
        ),
      ];

      final blocksT3 = groupTranscript(
        entries: entriesT3,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );
      final groupT3 = blocksT3.whereType<StepsGroupBlock>().first;
      final toolT3 = groupT3.steps.whereType<ToolStep>().first;

      // ToolStep ID is perfectly preserved from live to committed!
      expect(toolT3.id, 'compile_call_99');
      assertTranscriptCoverage(inputEntries: entriesT3, blocks: blocksT3);
    });

    test('TranscriptLiveState.fromSession derives error and abort flags correctly', () {
      final sessionRunning = SessionState(
        sessionId: 's1',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        streamingThinkingBlocks: {0: 'thinking...'},
        streamingTextBlocks: {0: 'output text'},
        activeToolCalls: {
          'c1': const ToolExecutionState(
            toolCallId: 'c1',
            toolName: 'read',
            isRunning: true,
          ),
        },
      );

      final liveRunning = TranscriptLiveState.fromSession(sessionRunning);
      expect(liveRunning.isRunning, isTrue);
      expect(liveRunning.streamingThinking, 'thinking...');
      expect(liveRunning.streamingText, 'output text');
      expect(liveRunning.activeToolCalls.length, 1);
      expect(liveRunning.hasError, isFalse);
      expect(liveRunning.aborted, isFalse);

      final sessionError = sessionRunning.copyWith(
        agentStatus: AgentStatus.workerError,
      );
      final liveError = TranscriptLiveState.fromSession(sessionError);
      expect(liveError.hasError, isTrue);

      final sessionAborted = SessionState(
        sessionId: 's2',
        cwd: '/repo',
        entries: [
          const SessionEntry(
            id: 'e1',
            role: 'assistant',
            text: '',
            timestamp: 100,
            metadata: {'stopReason': 'aborted'},
          ),
        ],
      );
      final liveAborted = TranscriptLiveState.fromSession(sessionAborted);
      expect(liveAborted.aborted, isTrue);
    });

    test('turnId stability: override set while optimistic survives reducer applying committed message', () {
      final notifier = StepGroupExpansionNotifier();

      // Initial state with optimistic user entry usr_1001
      var session = const SessionState(
        sessionId: 's_turn_test',
        cwd: '/test',
        entries: [
          SessionEntry(
            id: 'usr_1001',
            role: 'user',
            text: 'Fix the crash',
            timestamp: 1000,
          ),
          SessionEntry(
            id: 'asst_1',
            role: 'assistant',
            text: '',
            thinking: 'Analyzing backtrace',
            timestamp: 1100,
          ),
        ],
      );

      final initialBlocks = groupTranscript(
        entries: session.entries,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );

      final initialGroup = initialBlocks.whereType<StepsGroupBlock>().single;
      expect(initialGroup.turnId, 'usr_1001');
      expect(initialGroup.groupId, 'steps_usr_1001');

      // User sets override while optimistic (e.g. explicitly collapsed)
      notifier.setGroupOverride(initialGroup.turnId, false);
      expect(
        notifier.isGroupExpanded(
          turnId: initialGroup.turnId,
          isRunning: false,
          autoCollapse: false,
        ),
        isFalse,
      );

      // Reducer applies committed message from daemon (new id msg_comm_555)
      session = reduceSessionState(
        session,
        const MessageCompletedEvent(
          protocol: 1,
          id: 'evt_1',
          ts: 1002,
          sessionId: 's_turn_test',
          seq: 1,
          payload: {
            'message': {
              'id': 'msg_comm_555',
              'role': 'user',
              'content': 'Fix the crash',
              'timestamp': 1000,
            },
          },
        ),
      );

      // Verify metadata preserves optimisticId
      final committedUserEntry = session.entries[0];
      expect(committedUserEntry.id, 'msg_comm_555');
      expect(committedUserEntry.metadata?['optimisticId'], 'usr_1001');

      // Re-group transcript
      final updatedBlocks = groupTranscript(
        entries: session.entries,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );

      final updatedGroup = updatedBlocks.whereType<StepsGroupBlock>().single;
      // turnId and groupId remain stable!
      expect(updatedGroup.turnId, 'usr_1001');
      expect(updatedGroup.groupId, 'steps_usr_1001');

      // Expansion override is still recognized
      expect(
        notifier.isGroupExpanded(
          turnId: updatedGroup.turnId,
          isRunning: false,
          autoCollapse: false,
        ),
        isFalse,
      );
    });

    test('filters junk and internal entries before partitioning without loss of valid messages', () {
      final entries = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Do some work',
          timestamp: 1000,
        ),
        const SessionEntry(
          id: 'sys1',
          role: 'system',
          text: 'System instruction update',
          timestamp: 1050,
        ),
        const SessionEntry(
          id: 'asst1',
          role: 'assistant',
          text: 'Step 1 text',
          timestamp: 1100,
          toolCalls: [
            ToolExecutionState(
              toolCallId: 't1',
              toolName: 'read',
              output: 'data',
            ),
          ],
        ),
        const SessionEntry(
          id: 'tool_res1',
          role: 'toolResult',
          text: 'result data',
          timestamp: 1150,
        ),
        const SessionEntry(
          id: 'junk_asst',
          role: 'assistant',
          text: '(exit 0, no output)',
          timestamp: 1200,
        ),
        const SessionEntry(
          id: 'cust_hidden',
          role: 'custom',
          text: 'hidden extension data',
          metadata: {'display': false},
          timestamp: 1250,
        ),
        const SessionEntry(
          id: 'asst2',
          role: 'assistant',
          text: 'All done cleanly.',
          timestamp: 1300,
        ),
      ];

      final blocks = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.always,
        live: TranscriptLiveState.empty,
      );

      // Verify no internal or junk entries appear anywhere
      final allEntryIds = <String>[];
      for (final b in blocks) {
        if (b is EntryBlock) allEntryIds.add(b.entry.id);
        if (b is FinalTextBlock) allEntryIds.add(b.entry.id);
      }
      expect(allEntryIds, isNot(contains('sys1')));
      expect(allEntryIds, isNot(contains('tool_res1')));
      expect(allEntryIds, isNot(contains('junk_asst')));
      expect(allEntryIds, isNot(contains('cust_hidden')));

      // Final text is asst2
      final finalBlock = blocks.whereType<FinalTextBlock>().single;
      expect(finalBlock.entry.id, 'asst2');
      expect(finalBlock.text, 'All done cleanly.');

      // Coverage passes against cleaned input
      assertTranscriptCoverage(inputEntries: entries, blocks: blocks);
    });

    test('live streaming data only used when live.isRunning is true', () {
      final entries = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Explain quantum computing',
          timestamp: 1000,
        ),
        const SessionEntry(
          id: 'asst1',
          role: 'assistant',
          text: 'Quantum computing uses qubits.',
          thinking: 'Think about qubits',
          timestamp: 1100,
        ),
      ];

      // isRunning is FALSE, but streamingText and streamingThinking contain stale leftovers
      const staleLive = TranscriptLiveState(
        isRunning: false,
        streamingText: 'Stale stream tail that was not cleared',
        streamingThinking: 'Stale stream thinking',
        activeToolCalls: [
          ToolExecutionState(
            toolCallId: 't_stale',
            toolName: 'stale_tool',
            isRunning: true,
          ),
        ],
      );

      final blocks = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.withThinking,
        live: staleLive,
      );

      // Committed entries decide final text
      final finalBlock = blocks.whereType<FinalTextBlock>().single;
      expect(finalBlock.text, 'Quantum computing uses qubits.');

      // NO LiveTailBlock emitted
      expect(blocks.whereType<LiveTailBlock>(), isEmpty);

      // Steps group has only committed thinking, no live thinking step or active tool
      final group = blocks.whereType<StepsGroupBlock>().single;
      expect(group.steps.length, 1);
      expect(group.steps[0].id, 'asst1_thinking');
      expect(group.steps.whereType<ToolStep>(), isEmpty);
    });

    test('trailing assistant entries with empty text and no tools allow preceding entry to be final text', () {
      final entries = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Compute answer',
          timestamp: 1000,
        ),
        const SessionEntry(
          id: 'asst1',
          role: 'assistant',
          text: 'The answer is 42.',
          thinking: 'Initial calculation',
          timestamp: 1100,
        ),
        const SessionEntry(
          id: 'asst2',
          role: 'assistant',
          text: '',
          thinking: 'Post-reflection thought 1',
          timestamp: 1200,
        ),
        const SessionEntry(
          id: 'asst3',
          role: 'assistant',
          text: '   ',
          thinking: 'Post-reflection thought 2',
          timestamp: 1300,
        ),
      ];

      final blocks = groupTranscript(
        entries: entries,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );

      // Final text is asst1
      final finalBlock = blocks.whereType<FinalTextBlock>().single;
      expect(finalBlock.entry.id, 'asst1');
      expect(finalBlock.text, 'The answer is 42.');

      // Steps group contains all 3 thinking steps
      final group = blocks.whereType<StepsGroupBlock>().single;
      expect(group.steps.length, 3);
      expect(group.steps.map((s) => s.id), [
        'asst1_thinking',
        'asst2_thinking',
        'asst3_thinking',
      ]);

      assertTranscriptCoverage(inputEntries: entries, blocks: blocks);
    });

    test('normalizes timestamps across mixed seconds and milliseconds in elapsed computation', () {
      // Direct unit test of normalizeTimestampToMs
      expect(normalizeTimestampToMs(1000), 1000); // synthetic ms
      expect(normalizeTimestampToMs(1710000000), 1710000000000); // Unix seconds -> ms
      expect(normalizeTimestampToMs(1710000000000), 1710000000000); // Unix ms unchanged

      // User entry in seconds (1710000000), assistant in milliseconds (1710000004500) -> 4500ms
      final entriesMixed = [
        const SessionEntry(
          id: 'u1',
          role: 'user',
          text: 'Do task',
          timestamp: 1710000000, // seconds
        ),
        const SessionEntry(
          id: 'asst1',
          role: 'assistant',
          text: '',
          thinking: 'Thinking about it',
          timestamp: 1710000002000,
        ),
        const SessionEntry(
          id: 'asst2',
          role: 'assistant',
          text: 'Done!',
          timestamp: 1710000004500, // ms
        ),
      ];

      final blocksMixed = groupTranscript(
        entries: entriesMixed,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );
      final groupMixed = blocksMixed.whereType<StepsGroupBlock>().single;
      expect(groupMixed.elapsed, const Duration(milliseconds: 4500));

      // Both in seconds: 1710000000 to 1710000005 -> 5 seconds
      final entriesSeconds = [
        const SessionEntry(
          id: 'u2',
          role: 'user',
          text: 'Do task 2',
          timestamp: 1710000000, // seconds
        ),
        const SessionEntry(
          id: 'asst2_1',
          role: 'assistant',
          text: '',
          thinking: 'Thinking',
          timestamp: 1710000002, // seconds
        ),
        const SessionEntry(
          id: 'asst2_2',
          role: 'assistant',
          text: 'Done 2!',
          timestamp: 1710000005, // seconds
        ),
      ];

      final blocksSeconds = groupTranscript(
        entries: entriesSeconds,
        mode: StepGroupingMode.withThinking,
        live: TranscriptLiveState.empty,
      );
      final groupSeconds = blocksSeconds.whereType<StepsGroupBlock>().single;
      expect(groupSeconds.elapsed, const Duration(seconds: 5));
    });
  });

  group('step_grouping_settings - persistence & model', () {
    test('defaults to mode withThinking and autoCollapse true', () {
      const settings = StepGroupingSettings();
      expect(settings.mode, StepGroupingMode.withThinking);
      expect(settings.autoCollapse, isTrue);
    });

    test('roundtrips toJson and fromJson', () {
      const settings = StepGroupingSettings(
        mode: StepGroupingMode.always,
        autoCollapse: false,
      );
      final json = settings.toJson();
      final restored = StepGroupingSettings.fromJson(json);
      expect(restored.mode, StepGroupingMode.always);
      expect(restored.autoCollapse, isFalse);
      expect(restored, equals(settings));
    });

    test('tolerant to invalid and missing json fields', () {
      final fallback = StepGroupingSettings.fromJson({
        'mode': 'unknown_mode',
        'autoCollapse': null,
      });
      expect(fallback.mode, StepGroupingMode.withThinking);
      expect(fallback.autoCollapse, isTrue);

      final emptyJson = StepGroupingSettings.fromJson(null);
      expect(emptyJson.mode, StepGroupingMode.withThinking);
      expect(emptyJson.autoCollapse, isTrue);
    });

    test('StepGroupingSettingsNotifier persists changes to injected file', () {
      final tempDir = Directory.systemTemp.createTempSync('step_settings_test');
      final file = File('${tempDir.path}/step_settings.json');

      try {
        final notifier = StepGroupingSettingsNotifier(storageFile: file);
        expect(notifier.state.mode, StepGroupingMode.withThinking);
        expect(notifier.state.autoCollapse, isTrue);

        notifier.setMode(StepGroupingMode.off);
        notifier.setAutoCollapse(false);

        expect(notifier.state.mode, StepGroupingMode.off);
        expect(notifier.state.autoCollapse, isFalse);
        expect(file.existsSync(), isTrue);

        // Reload from same file
        final reloadedNotifier = StepGroupingSettingsNotifier(storageFile: file);
        expect(reloadedNotifier.state.mode, StepGroupingMode.off);
        expect(reloadedNotifier.state.autoCollapse, isFalse);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('step_group_expansion - state & notifier', () {
    test('isGroupExpanded logic: manual override beats auto-collapse, auto-collapse off keeps open', () {
      final notifier = StepGroupExpansionNotifier();

      // Case 1: autoCollapse: true, isRunning: false -> default closed
      expect(
        notifier.isGroupExpanded(
          turnId: 'u1',
          isRunning: false,
          autoCollapse: true,
        ),
        isFalse,
      );

      // Case 2: manual toggle opens group even when finished and autoCollapse is true
      notifier.toggleGroup('u1', false);
      expect(
        notifier.isGroupExpanded(
          turnId: 'u1',
          isRunning: false,
          autoCollapse: true,
        ),
        isTrue,
      );

      // Case 3: autoCollapse: false keeps group open unless manually collapsed
      expect(
        notifier.isGroupExpanded(
          turnId: 'u2',
          isRunning: false,
          autoCollapse: false,
        ),
        isTrue,
      );

      // Case 4: isRunning: true keeps group open
      expect(
        notifier.isGroupExpanded(
          turnId: 'u3',
          isRunning: true,
          autoCollapse: true,
        ),
        isTrue,
      );

      // Step expansion toggle
      expect(notifier.isStepExpanded('step_1'), isFalse);
      notifier.toggleStep('step_1');
      expect(notifier.isStepExpanded('step_1'), isTrue);
      notifier.toggleStep('step_1');
      expect(notifier.isStepExpanded('step_1'), isFalse);
    });

    test('bounded memory: LRU eviction prevents unbounded growth', () {
      final notifier = StepGroupExpansionNotifier();

      // Add overrides up to capacity
      for (int i = 0; i < StepGroupExpansionNotifier.maxGroupOverrides + 10; i++) {
        notifier.toggleGroup('turn_$i', false);
      }

      // Overrides map must be capped
      expect(
        notifier.state.groupOverrides.length,
        lessThanOrEqualTo(StepGroupExpansionNotifier.maxGroupOverrides),
      );

      // Oldest turn should have been evicted
      expect(notifier.state.groupOverrides.containsKey('turn_0'), isFalse);
      expect(
        notifier.state.groupOverrides.containsKey(
          'turn_${StepGroupExpansionNotifier.maxGroupOverrides + 9}',
        ),
        isTrue,
      );
    });

    test('state persists across Riverpod provider re-read / simulates widget rebuild', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const sessionId = 'session_test_123';
      final notifier = container.read(stepGroupExpansionProvider(sessionId).notifier);

      expect(
        notifier.isGroupExpanded(turnId: 'u1', isRunning: false, autoCollapse: true),
        isFalse,
      );

      notifier.toggleGroup('u1', false);
      expect(
        container
            .read(stepGroupExpansionProvider(sessionId))
            .isGroupExpanded(turnId: 'u1', isRunning: false, autoCollapse: true),
        isTrue,
      );

      // Simulate widget rebuild watching the provider
      final stateAfterRebuild = container.read(stepGroupExpansionProvider(sessionId));
      expect(
        stateAfterRebuild.isGroupExpanded(
          turnId: 'u1',
          isRunning: false,
          autoCollapse: true,
        ),
        isTrue,
      );
    });

    test('true LRU eviction in StepGroupExpansionNotifier and protection of running turn', () {
      final notifier = StepGroupExpansionNotifier();

      // Add 500 overrides
      for (int i = 0; i < 500; i++) {
        notifier.setGroupOverride('turn_$i', true);
      }

      // Re-inserting / updating turn_0 moves it to the most recent position
      notifier.setGroupOverride('turn_0', false);

      // Adding turn_500 causes eviction of the oldest (turn_1, since turn_0 was refreshed)
      notifier.setGroupOverride('turn_500', true);

      expect(notifier.state.groupOverrides.containsKey('turn_0'), isTrue);
      expect(notifier.state.groupOverrides.containsKey('turn_1'), isFalse);
      expect(notifier.state.groupOverrides.containsKey('turn_500'), isTrue);

      // Protection of running turn
      notifier.setActiveTurnId('turn_0');
      // Fill overrides so turn_0 would normally be oldest candidate
      for (int i = 501; i < 1000; i++) {
        notifier.setGroupOverride('turn_$i', true);
      }
      // Running turn override must never be evicted
      expect(notifier.state.groupOverrides.containsKey('turn_0'), isTrue);

      // True LRU in setStepExpanded
      final stepNotifier = StepGroupExpansionNotifier();
      for (int i = 0; i < 1000; i++) {
        stepNotifier.setStepExpanded('step_$i', true);
      }
      // Refresh step_0
      stepNotifier.setStepExpanded('step_0', true);
      // Add step_1000 -> evicts step_1, preserves step_0
      stepNotifier.setStepExpanded('step_1000', true);
      expect(stepNotifier.isStepExpanded('step_0'), isTrue);
      expect(stepNotifier.isStepExpanded('step_1'), isFalse);
    });
  });

  group('language_settings - AppStrings step grouping localization', () {
    test('all step grouping strings are localized in both Italian and English', () {
      const stringsIt = AppStrings(AppLanguage.it);
      const stringsEn = AppStrings(AppLanguage.en);

      expect(stringsIt.stepGroupingSectionTitle, 'Raggruppamento passaggi');
      expect(stringsEn.stepGroupingSectionTitle, 'Step grouping');

      expect(stringsIt.stepGroupingModeOff, 'Disattivato');
      expect(stringsEn.stepGroupingModeOff, 'Off');

      expect(stringsIt.stepGroupingModeWithThinking, 'Con ragionamento');
      expect(stringsEn.stepGroupingModeWithThinking, 'With thinking');

      expect(stringsIt.stepGroupingModeAlways, 'Sempre');
      expect(stringsEn.stepGroupingModeAlways, 'Always');

      expect(stringsIt.stepGroupWorking, 'Elaborazione…');
      expect(stringsEn.stepGroupWorking, 'Working…');

      expect(stringsIt.stepGroupCompletedIn(3, '2s'), 'Completati 3 passaggi in 2s');
      expect(stringsEn.stepGroupCompletedIn(3, '2s'), 'Completed 3 steps in 2s');

      expect(stringsIt.stepGroupCompleted(4), 'Completati 4 passaggi');
      expect(stringsEn.stepGroupCompleted(4), 'Completed 4 steps');

      expect(stringsIt.stepGroupFinished(5), 'Terminato con 5 passaggi');
      expect(stringsEn.stepGroupFinished(5), 'Finished with 5 steps');

      expect(
        stringsIt.stepGroupStoppedWithErrors(2),
        'Interrotto con errori dopo 2 passaggi',
      );
      expect(
        stringsEn.stepGroupStoppedWithErrors(2),
        'Stopped with errors after 2 steps',
      );

      expect(stringsIt.stepGroupShowAll, 'Mostra tutti');
      expect(stringsEn.stepGroupShowAll, 'Show all');

      expect(stringsIt.stepGroupShowLess, 'Mostra meno');
      expect(stringsEn.stepGroupShowLess, 'Show less');

      expect(stringsIt.stepGroupInput, 'Input');
      expect(stringsEn.stepGroupInput, 'Input');

      expect(stringsIt.stepGroupOutput, 'Output');
      expect(stringsEn.stepGroupOutput, 'Output');

      // Helper labels
      expect(
        stringsIt.stepGroupingModeLabel(StepGroupingMode.withThinking),
        'Con ragionamento',
      );
      expect(
        stringsEn.stepGroupingModeLabel(StepGroupingMode.always),
        'Always',
      );
    });

    test('pluralization in AppStrings for 1 step vs multiple steps', () {
      const stringsIt = AppStrings(AppLanguage.it);
      const stringsEn = AppStrings(AppLanguage.en);

      // 1 step singular
      expect(stringsIt.stepGroupCompletedIn(1, '2s'), 'Completato 1 passaggio in 2s');
      expect(stringsEn.stepGroupCompletedIn(1, '2s'), 'Completed 1 step in 2s');

      expect(stringsIt.stepGroupCompleted(1), 'Completato 1 passaggio');
      expect(stringsEn.stepGroupCompleted(1), 'Completed 1 step');

      expect(stringsIt.stepGroupFinished(1), 'Terminato con 1 passaggio');
      expect(stringsEn.stepGroupFinished(1), 'Finished with 1 step');

      expect(
        stringsIt.stepGroupStoppedWithErrors(1),
        'Interrotto con errori dopo 1 passaggio',
      );
      expect(
        stringsEn.stepGroupStoppedWithErrors(1),
        'Stopped with errors after 1 step',
      );

      // > 1 step plural
      expect(stringsIt.stepGroupCompletedIn(2, '2s'), 'Completati 2 passaggi in 2s');
      expect(stringsEn.stepGroupCompletedIn(2, '2s'), 'Completed 2 steps in 2s');

      expect(stringsIt.stepGroupCompleted(2), 'Completati 2 passaggi');
      expect(stringsEn.stepGroupCompleted(2), 'Completed 2 steps');

      expect(stringsIt.stepGroupFinished(2), 'Terminato con 2 passaggi');
      expect(stringsEn.stepGroupFinished(2), 'Finished with 2 steps');

      expect(
        stringsIt.stepGroupStoppedWithErrors(2),
        'Interrotto con errori dopo 2 passaggi',
      );
      expect(
        stringsEn.stepGroupStoppedWithErrors(2),
        'Stopped with errors after 2 steps',
      );
    });
  });
}
