import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/transcript/step_grouping_settings.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/transcript_grouping.dart';
import 'package:pi_frame/features/transcript/step_group_expansion.dart';
import 'package:pi_frame/features/transcript/steps_group.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [FrameTokens.dark],
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('Step Grouping Widget & TranscriptView Integration Tests', () {
    testWidgets(
      '1. grouping with alternating thinking/tool calls renders group + final text outside',
      (tester) async {
        const sid = 'session_grouping_1';
        final userEntry = SessionEntry(
          id: 'user_1',
          role: 'user',
          text: 'Do some work for me',
          timestamp: 1000,
        );
        final asst1 = SessionEntry(
          id: 'asst_1',
          role: 'assistant',
          text: '',
          thinking: 'First thought on the problem.',
          toolCalls: const [
            ToolExecutionState(
              toolCallId: 'tool_call_1',
              toolName: 'read',
              args: {'path': 'lib/a.dart'},
              output: 'void main() {}',
              isRunning: false,
              startedAt: 1100,
              durationMs: 50,
            ),
          ],
          timestamp: 1200,
        );
        final asst2 = SessionEntry(
          id: 'asst_2',
          role: 'assistant',
          text: '',
          thinking: 'Second thought after inspecting the code.',
          toolCalls: const [
            ToolExecutionState(
              toolCallId: 'tool_call_2',
              toolName: 'bash',
              args: {'command': 'echo done'},
              output: 'done',
              isRunning: false,
              startedAt: 1250,
              durationMs: 80,
            ),
          ],
          timestamp: 1400,
        );
        final asstFinal = SessionEntry(
          id: 'asst_final',
          role: 'assistant',
          text: 'Here is the final answer to your question!',
          timestamp: 1600,
        );

        final notifier = SessionStateNotifier(sid, null)
          ..state = SessionState(
            sessionId: sid,
            cwd: '/repo',
            entries: [userEntry, asst1, asst2, asstFinal],
          );

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              daemonEndpointProvider.overrideWith((ref) async => null),
              sessionStateFamily(sid).overrideWith((ref) => notifier),
              stepGroupingSettingsProvider.overrideWith(
                (ref) => StepGroupingSettingsNotifier()
                  ..setMode(StepGroupingMode.withThinking),
              ),
            ],
            child: const TranscriptView(sessionId: sid),
          ),
        );
        await tester.pumpAndSettle();

        // StepsGroup must be present in the tree
        expect(find.byType(StepsGroup), findsOneWidget);

        // Final text must be present
        expect(
          find.text('Here is the final answer to your question!'),
          findsOneWidget,
        );

        // Final text is outside StepsGroup
        expect(
          find.descendant(
            of: find.byType(StepsGroup),
            matching: find.text('Here is the final answer to your question!'),
          ),
          findsNothing,
        );

        // Assistant label for final text is rendered
        expect(find.text('Assistente'), findsOneWidget);
      },
    );

    testWidgets(
      '2. group open while streaming with "Working…" + latest step',
      (tester) async {
        const sid = 'session_grouping_2';
        final userEntry = SessionEntry(
          id: 'user_live',
          role: 'user',
          text: 'Analyze the codebase',
          timestamp: 1000,
        );

        final notifier = SessionStateNotifier(sid, null)
          ..state = SessionState(
            sessionId: sid,
            cwd: '/repo',
            entries: [userEntry],
            agentStatus: AgentStatus.working,
            activeToolCalls: const {
              'tool_live_1': ToolExecutionState(
                toolCallId: 'tool_live_1',
                toolName: 'read',
                args: {'path': 'lib/features/transcript/transcript_view.dart'},
                output: 'reading file...',
                isRunning: true,
                startedAt: 1100,
              ),
            },
          );

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              daemonEndpointProvider.overrideWith((ref) async => null),
              sessionStateFamily(sid).overrideWith((ref) => notifier),
              stepGroupingSettingsProvider.overrideWith(
                (ref) => StepGroupingSettingsNotifier()
                  ..setMode(StepGroupingMode.always),
              ),
            ],
            child: const TranscriptView(sessionId: sid),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Group must be present
        expect(find.byType(StepsGroup), findsOneWidget);

        // Header shows "Working…" or Italian "Elaborazione…"
        final workingFinder = find.textContaining('Working…');
        final elaborazioneFinder = find.textContaining('Elaborazione…');
        expect(
          workingFinder.evaluate().isNotEmpty ||
              elaborazioneFinder.evaluate().isNotEmpty,
          isTrue,
        );

        // Tool name and abbreviated path in header label
        expect(find.textContaining('read'), findsWidgets);

        // Spinner is shown in the header
        expect(find.byType(CircularProgressIndicator), findsWidgets);

        // Body is open: the active tool step item is rendered inside
        expect(
          find.byKey(const ValueKey('tool_step_tool_live_1')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '3. auto-collapse at turn end (state transitions running->settled collapses)',
      (tester) async {
        const sid = 'session_grouping_3';
        final userEntry = SessionEntry(
          id: 'user_3',
          role: 'user',
          text: 'Run tests',
          timestamp: 1000,
        );

        final notifier = SessionStateNotifier(sid, null)
          ..state = SessionState(
            sessionId: sid,
            cwd: '/repo',
            entries: [userEntry],
            agentStatus: AgentStatus.working,
            activeToolCalls: const {
              'tool_run': ToolExecutionState(
                toolCallId: 'tool_run',
                toolName: 'bash',
                args: {'command': 'flutter test'},
                output: 'All tests passed',
                isRunning: true,
                startedAt: 1050,
              ),
            },
          );

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              daemonEndpointProvider.overrideWith((ref) async => null),
              sessionStateFamily(sid).overrideWith((ref) => notifier),
              stepGroupingSettingsProvider.overrideWith(
                (ref) => StepGroupingSettingsNotifier()
                  ..setMode(StepGroupingMode.always)
                  ..setAutoCollapse(true),
              ),
            ],
            child: const TranscriptView(sessionId: sid),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // While running, group body is visible (open)
        expect(
          find.byKey(const ValueKey('tool_step_tool_run')),
          findsOneWidget,
        );

        // Transition from running to settled
        final committedEntry = SessionEntry(
          id: 'asst_3',
          role: 'assistant',
          text: 'Tests completed successfully.',
          toolCalls: const [
            ToolExecutionState(
              toolCallId: 'tool_run',
              toolName: 'bash',
              args: {'command': 'flutter test'},
              output: 'All tests passed',
              isRunning: false,
              startedAt: 1050,
              durationMs: 300,
            ),
          ],
          timestamp: 1400,
        );

        notifier.state = notifier.state.copyWith(
          agentStatus: AgentStatus.idle,
          activeToolCalls: const {},
          entries: [userEntry, committedEntry],
        );
        await tester.pumpAndSettle();

        // Now group must be auto-collapsed: the tool step inside the body is gone
        expect(
          find.byKey(const ValueKey('tool_step_tool_run')),
          findsNothing,
        );

        // Header shows completion status
        final completedFinder = find.textContaining('Completed');
        final completatiFinder = find.textContaining('Completat');
        expect(
          completedFinder.evaluate().isNotEmpty ||
              completatiFinder.evaluate().isNotEmpty,
          isTrue,
        );
      },
    );

    testWidgets(
      '4. manual expand before end -> stays expanded after end (override wins) and manual collapse while running stays collapsed',
      (tester) async {
        const sid = 'session_grouping_4';
        final userEntry = SessionEntry(
          id: 'user_4',
          role: 'user',
          text: 'Do some work',
          timestamp: 1000,
        );

        final notifier = SessionStateNotifier(sid, null)
          ..state = SessionState(
            sessionId: sid,
            cwd: '/repo',
            entries: [userEntry],
            agentStatus: AgentStatus.working,
            activeToolCalls: const {
              'tool_4': ToolExecutionState(
                toolCallId: 'tool_4',
                toolName: 'read',
                args: {'path': 'a.txt'},
                output: 'content',
                isRunning: true,
                startedAt: 1100,
              ),
            },
          );

        final container = ProviderContainer(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            sessionStateFamily(sid).overrideWith((ref) => notifier),
            stepGroupingSettingsProvider.overrideWith(
              (ref) => StepGroupingSettingsNotifier()
                ..setMode(StepGroupingMode.always)
                ..setAutoCollapse(true),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [FrameTokens.dark],
              ),
              home: const Scaffold(body: TranscriptView(sessionId: sid)),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Group is open while running
        expect(find.byKey(const ValueKey('tool_step_tool_4')), findsOneWidget);

        // 4a. Manual collapse while running: tap the header
        await tester.tap(
          find.byKey(const ValueKey('step_group_header_steps_user_4')),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Should now be collapsed
        expect(find.byKey(const ValueKey('tool_step_tool_4')), findsNothing);

        // Transition to settled: manual collapse stays collapsed
        notifier.state = notifier.state.copyWith(
          agentStatus: AgentStatus.idle,
          activeToolCalls: const {},
          entries: [
            userEntry,
            const SessionEntry(
              id: 'asst_4',
              role: 'assistant',
              text: 'Done',
              toolCalls: [
                ToolExecutionState(
                  toolCallId: 'tool_4',
                  toolName: 'read',
                  args: {'path': 'a.txt'},
                  output: 'content',
                  isRunning: false,
                  startedAt: 1100,
                  durationMs: 100,
                ),
              ],
              timestamp: 1250,
            ),
          ],
        );
        await tester.pumpAndSettle();

        // Stays collapsed
        expect(find.byKey(const ValueKey('tool_step_tool_4')), findsNothing);

        // 4b. Now tap to manually expand while settled
        await tester.tap(
          find.byKey(const ValueKey('step_group_header_steps_user_4')),
        );
        await tester.pumpAndSettle();

        // Group is now expanded
        expect(find.byKey(const ValueKey('tool_step_tool_4')), findsOneWidget);

        // Emit new streaming delta to verify override wins
        notifier.state = notifier.state.copyWith(
          streamingTextBlocks: const {0: 'new delta'},
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Override wins: stays expanded!
        expect(find.byKey(const ValueKey('tool_step_tool_4')), findsOneWidget);
      },
    );

    testWidgets(
      '5. error turn shows error icon and "Stopped with errors…"',
      (tester) async {
        const sid = 'session_grouping_5';
        final userEntry = SessionEntry(
          id: 'user_5',
          role: 'user',
          text: 'Failing command',
          timestamp: 1000,
        );
        final asstEntry = SessionEntry(
          id: 'asst_5',
          role: 'assistant',
          text: 'Encountered failure',
          toolCalls: const [
            ToolExecutionState(
              toolCallId: 'tool_fail',
              toolName: 'bash',
              args: {'command': 'exit 1'},
              output: 'command not found',
              isRunning: false,
              isError: true,
              startedAt: 1100,
              durationMs: 40,
            ),
          ],
          timestamp: 1200,
        );

        final notifier = SessionStateNotifier(sid, null)
          ..state = SessionState(
            sessionId: sid,
            cwd: '/repo',
            entries: [userEntry, asstEntry],
            agentStatus: AgentStatus.idle,
          );

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              daemonEndpointProvider.overrideWith((ref) async => null),
              sessionStateFamily(sid).overrideWith((ref) => notifier),
              stepGroupingSettingsProvider.overrideWith(
                (ref) => StepGroupingSettingsNotifier()
                  ..setMode(StepGroupingMode.always),
              ),
            ],
            child: const TranscriptView(sessionId: sid),
          ),
        );
        await tester.pumpAndSettle();

        // Error icon is shown in header
        expect(find.byIcon(Icons.error_outline), findsOneWidget);

        // Header shows stopped with errors
        final errorTextEn = find.textContaining('Stopped with errors');
        final errorTextIt = find.textContaining('Interrotto con errori');
        expect(
          errorTextEn.evaluate().isNotEmpty ||
              errorTextIt.evaluate().isNotEmpty,
          isTrue,
        );
      },
    );

    testWidgets(
      '6. tool row expand shows input/output with Show all for long output',
      (tester) async {
        const sid = 'session_grouping_6';
        final longOutput = List.generate(30, (i) => 'Line $i of output text').join('\n');
        final block = StepsGroupBlock(
          groupId: 'steps_test_6',
          turnId: 'turn_6',
          steps: [
            ToolStep(
              id: 'tool_step_6',
              tool: ToolExecutionState(
                toolCallId: 'tool_call_6',
                toolName: 'bash',
                args: const {'command': 'cat bigfile.txt'},
                output: longOutput,
                isRunning: false,
                durationMs: 50,
              ),
            ),
          ],
          isRunning: false,
          hasError: false,
          aborted: false,
          stepCount: 1,
        );

        final container = ProviderContainer(
          overrides: [
            stepGroupingSettingsProvider.overrideWith(
              (ref) => StepGroupingSettingsNotifier()
                ..setAutoCollapse(false),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Initially expand group
        container.read(stepGroupExpansionProvider(sid).notifier)
          .setGroupOverride('turn_6', true);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [FrameTokens.dark],
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: StepsGroup(
                    block: block,
                    sessionId: sid,
                    tokens: FrameTokens.dark,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // ToolStep row header is visible
        expect(
          find.byKey(const ValueKey('tool_step_header_tool_step_6')),
          findsOneWidget,
        );

        // Expanded detail is not yet visible
        expect(
          find.byKey(const ValueKey('tool_step_expanded_tool_step_6')),
          findsNothing,
        );

        // Tap the tool row header to expand details
        await tester.tap(
          find.byKey(const ValueKey('tool_step_header_tool_step_6')),
        );
        await tester.pumpAndSettle();

        // Now expanded detail is visible
        expect(
          find.byKey(const ValueKey('tool_step_expanded_tool_step_6')),
          findsOneWidget,
        );

        // Shows Input label and Output label
        expect(find.text('Input'), findsOneWidget);
        expect(find.text('Output'), findsOneWidget);

        // Shows "Show all" or "Mostra tutti" button
        final showAllBtn = find.byKey(
          const ValueKey('tool_step_toggle_output_truncation'),
        );
        expect(showAllBtn, findsOneWidget);

        // Before clicking Show all, Line 29 is truncated
        expect(find.textContaining('Line 29 of output text'), findsNothing);

        // Tap "Show all"
        await tester.tap(showAllBtn);
        await tester.pumpAndSettle();

        // Now full output is visible including Line 29
        expect(find.textContaining('Line 29 of output text'), findsOneWidget);
      },
    );

    testWidgets(
      '7. thinking expand shows full text',
      (tester) async {
        const sid = 'session_grouping_7';
        final block = const StepsGroupBlock(
          groupId: 'steps_test_7',
          turnId: 'turn_7',
          steps: [
            ThinkingStep(
              id: 'thinking_step_7',
              text: 'First thought line\nDetailed thought analysis second line\nThird line',
            ),
          ],
          isRunning: false,
          hasError: false,
          aborted: false,
          stepCount: 1,
        );

        final container = ProviderContainer(
          overrides: [
            stepGroupingSettingsProvider.overrideWith(
              (ref) => StepGroupingSettingsNotifier()..setAutoCollapse(false),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Expand group
        container.read(stepGroupExpansionProvider(sid).notifier)
          .setGroupOverride('turn_7', true);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [FrameTokens.dark],
              ),
              home: Scaffold(
                body: StepsGroup(
                  block: block,
                  sessionId: sid,
                  tokens: FrameTokens.dark,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Thinking step header is visible
        expect(
          find.byKey(const ValueKey('thinking_step_header_thinking_step_7')),
          findsOneWidget,
        );

        // Collapsed initially: full SelectableText not shown
        expect(find.byType(SelectableText), findsNothing);

        // Tap thinking step header to expand
        await tester.tap(
          find.byKey(const ValueKey('thinking_step_header_thinking_step_7')),
        );
        await tester.pumpAndSettle();

        // Now full SelectableText is rendered with full thinking content
        expect(find.byType(SelectableText), findsOneWidget);
        expect(
          find.text('First thought line\nDetailed thought analysis second line\nThird line'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '8. mode off renders no group',
      (tester) async {
        const sid = 'session_grouping_8';
        final userEntry = SessionEntry(
          id: 'user_8',
          role: 'user',
          text: 'Hello off mode',
          timestamp: 1000,
        );
        final asstEntry = SessionEntry(
          id: 'asst_8',
          role: 'assistant',
          text: 'Answer in off mode',
          thinking: 'Some thought here',
          toolCalls: const [
            ToolExecutionState(
              toolCallId: 'tool_8',
              toolName: 'read',
              args: {'path': 'b.txt'},
              output: 'data',
              isRunning: false,
            ),
          ],
          timestamp: 1100,
        );

        final notifier = SessionStateNotifier(sid, null)
          ..state = SessionState(
            sessionId: sid,
            cwd: '/repo',
            entries: [userEntry, asstEntry],
          );

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              daemonEndpointProvider.overrideWith((ref) async => null),
              sessionStateFamily(sid).overrideWith((ref) => notifier),
              stepGroupingSettingsProvider.overrideWith(
                (ref) => StepGroupingSettingsNotifier()
                  ..setMode(StepGroupingMode.off),
              ),
            ],
            child: const TranscriptView(sessionId: sid),
          ),
        );
        await tester.pumpAndSettle();

        // In mode off, NO StepsGroup is rendered!
        expect(find.byType(StepsGroup), findsNothing);

        // Instead, normal entries are rendered directly
        expect(find.text('Hello off mode'), findsOneWidget);
        expect(find.text('Answer in off mode'), findsOneWidget);
        expect(find.text('Ragionamento'), findsOneWidget);
      },
    );

    testWidgets(
      '9. expansion survives re-render with new streaming deltas',
      (tester) async {
        const sid = 'session_grouping_9';
        final userEntry = SessionEntry(
          id: 'user_9',
          role: 'user',
          text: 'Streaming survival test',
          timestamp: 1000,
        );
        final asstEntry = SessionEntry(
          id: 'asst_9',
          role: 'assistant',
          text: 'Final response',
          thinking: 'Important thought to read',
          toolCalls: const [
            ToolExecutionState(
              toolCallId: 'tool_9',
              toolName: 'grep',
              args: {'pattern': 'search'},
              output: 'found 3 matches',
              isRunning: false,
            ),
          ],
          timestamp: 1100,
        );

        final notifier = SessionStateNotifier(sid, null)
          ..state = SessionState(
            sessionId: sid,
            cwd: '/repo',
            entries: [userEntry, asstEntry],
            agentStatus: AgentStatus.idle,
          );

        final container = ProviderContainer(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            sessionStateFamily(sid).overrideWith((ref) => notifier),
            stepGroupingSettingsProvider.overrideWith(
              (ref) => StepGroupingSettingsNotifier()
                ..setMode(StepGroupingMode.withThinking),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [FrameTokens.dark],
              ),
              home: const Scaffold(body: TranscriptView(sessionId: sid)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Expand the group
        await tester.tap(
          find.byKey(const ValueKey('step_group_header_steps_user_9')),
        );
        await tester.pumpAndSettle();

        // Expand the thinking step
        await tester.tap(
          find.byKey(const ValueKey('thinking_step_header_asst_9_thinking')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Important thought to read'), findsOneWidget);

        // Simulate incoming streaming deltas
        notifier.state = notifier.state.copyWith(
          streamingTextBlocks: const {0: 'new delta arriving'},
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Group is STILL expanded and thinking step is STILL expanded!
        expect(find.byType(StepsGroup), findsOneWidget);
        expect(find.text('Important thought to read'), findsOneWidget);
      },
    );

    testWidgets(
      '10. final text content identical to entry text',
      (tester) async {
        const sid = 'session_grouping_10';
        const rawFinalText =
            'Exact unaltered final text with **markdown**, `code`, and symbols: <>/!@#\$%^&*()';
        final userEntry = SessionEntry(
          id: 'user_10',
          role: 'user',
          text: 'Format question',
          timestamp: 1000,
        );
        final asstWithThinking = SessionEntry(
          id: 'asst_10_thinking',
          role: 'assistant',
          text: '',
          thinking: 'Pondering formatting',
          timestamp: 1050,
        );
        final asstFinal = SessionEntry(
          id: 'asst_10_final',
          role: 'assistant',
          text: rawFinalText,
          timestamp: 1100,
        );

        final notifier = SessionStateNotifier(sid, null)
          ..state = SessionState(
            sessionId: sid,
            cwd: '/repo',
            entries: [userEntry, asstWithThinking, asstFinal],
          );

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              daemonEndpointProvider.overrideWith((ref) async => null),
              sessionStateFamily(sid).overrideWith((ref) => notifier),
              stepGroupingSettingsProvider.overrideWith(
                (ref) => StepGroupingSettingsNotifier()
                  ..setMode(StepGroupingMode.withThinking),
              ),
            ],
            child: const TranscriptView(sessionId: sid),
          ),
        );
        await tester.pumpAndSettle();

        // In grouped mode, FinalTextBlock contains the exact text
        final blocks = groupTranscript(
          entries: [userEntry, asstWithThinking, asstFinal],
          mode: StepGroupingMode.withThinking,
          live: TranscriptLiveState.empty,
        );
        final finalBlock = blocks.whereType<FinalTextBlock>().single;
        expect(finalBlock.text, equals(rawFinalText));

        // And it is rendered on screen
        expect(
          find.textContaining('Exact unaltered final text'),
          findsOneWidget,
        );
      },
    );
  });
}
