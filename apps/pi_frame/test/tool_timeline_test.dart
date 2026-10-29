import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/tool_timeline/tool_card.dart';
import 'package:pi_frame/features/tool_timeline/tool_timeline.dart';
import 'package:pi_frame/features/transcript/thinking_block.dart';

void main() {
  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [FrameTokens.dark],
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  testWidgets('tool actions align with reasoning at narrow and wide widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [320.0, 700.0]) {
      tester.view.physicalSize = Size(width + 40, 1000);
      await tester.pumpWidget(wrapWithTheme(
        Center(
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ThinkingBlock(thinkingText: 'Checking the files'),
                const ToolTimeline(toolCalls: [
                  ToolExecutionState(
                    toolCallId: 'short',
                    toolName: 'read',
                    args: {'path': 'a'},
                    output: 'content',
                    durationMs: 42,
                  ),
                  ToolExecutionState(
                    toolCallId: 'long',
                    toolName: 'write',
                    args: {
                      'path': 'a/very/long/path/that/should/be/truncated/in/the/compact/layout/example.dart',
                    },
                    output: 'saved',
                    durationMs: 6000,
                  ),
                  ToolExecutionState(
                    toolCallId: 'no-output',
                    toolName: 'edit',
                    args: {'path': 'file.dart'},
                    isError: true,
                  ),
                  ToolExecutionState(
                    toolCallId: 'running',
                    toolName: 'bash',
                    args: {'command': 'git status'},
                    isRunning: true,
                  ),
                ]),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      final reasoningIcon = find.descendant(
        of: find.byType(ThinkingBlock),
        matching: find.byIcon(Icons.expand_more),
      );
      final reasoningX = tester.getCenter(reasoningIcon).dx;
      for (final id in ['short', 'long', 'running']) {
        final card = find.byKey(ValueKey(id));
        final icon = find.descendant(
          of: card,
          matching: find.byIcon(Icons.expand_more),
        );
        expect(tester.getCenter(icon).dx, closeTo(reasoningX, 0.01));
      }
      final completed = find.descendant(
        of: find.byKey(const ValueKey('short')),
        matching: find.byIcon(Icons.check_circle_outline),
      );
      final failed = find.descendant(
        of: find.byKey(const ValueKey('no-output')),
        matching: find.byIcon(Icons.error_outline),
      );
      expect(
        tester.getCenter(failed).dx,
        closeTo(tester.getCenter(completed).dx, 0.01),
      );
      final running = find.descendant(
        of: find.byKey(const ValueKey('running')),
        matching: find.byType(CircularProgressIndicator),
      );
      expect(
        tester.getCenter(running).dx,
        closeTo(tester.getCenter(completed).dx, 0.01),
      );
      await tester.tap(find.text('read'));
      await tester.pump();
      final expandedIcon = find.descendant(
        of: find.byKey(const ValueKey('short')),
        matching: find.byIcon(Icons.expand_less),
      );
      expect(tester.getCenter(expandedIcon).dx, closeTo(reasoningX, 0.01));
      await tester.tap(find.text('read'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('ToolCard displays tool name, highlighted path arg and duration', (tester) async {
    const tool = ToolExecutionState(
      toolCallId: 'call_1',
      toolName: 'read_file',
      args: {'path': 'lib/main.dart'},
      output: 'file contents',
      isRunning: false,
      isError: false,
      durationMs: 45,
    );

    await tester.pumpWidget(
      wrapWithTheme(
        const ToolCard(tool: tool),
      ),
    );

    expect(find.text('read_file'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('45ms'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('ToolTimeline renders multiple tool calls in sequence', (tester) async {
    final tools = [
      const ToolExecutionState(
        toolCallId: 'call_1',
        toolName: 'bash',
        args: {'command': 'pnpm test'},
        output: 'PASS',
        isRunning: false,
      ),
      const ToolExecutionState(
        toolCallId: 'call_2',
        toolName: 'edit_file',
        args: {'path': 'pubspec.yaml'},
        isRunning: true,
      ),
    ];

    await tester.pumpWidget(
      wrapWithTheme(
        ToolTimeline(toolCalls: tools),
      ),
    );

    expect(find.text('bash'), findsOneWidget);
    expect(find.text('edit_file'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('ToolCard remains collapsed by default even while tool is running', (tester) async {
    const tool = ToolExecutionState(
      toolCallId: 'run_call_1',
      toolName: 'bash',
      args: {'command': 'git status'},
      output: 'On branch main',
      isRunning: true,
    );

    await tester.pumpWidget(wrapWithTheme(const ToolCard(tool: tool)));

    // Collapsed by default: header shows toolName and command preview
    expect(find.text('bash'), findsOneWidget);
    expect(find.text('git status'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    // Body is NOT expanded
    expect(find.byKey(const ValueKey('tool-card-expanded-command')), findsNothing);

    // Clicking header expands the command
    await tester.tap(find.byType(TextButton));
    await tester.pump();

    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-card-expanded-command')), findsOneWidget);
  });
}
