import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/features/tool_timeline/tool_card.dart';
import 'package:pi_crust/features/tool_timeline/tool_timeline.dart';

void main() {
  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [CrustTokens.dark],
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

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
