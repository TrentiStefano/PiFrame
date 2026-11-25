// Half-width windows: pane headers keep their titles readable by moving their
// actions to a second line, and wide panes keep the single-line layout.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/transcript/subagent_panel.dart';
import 'package:pi_frame/features/transcript/subagents_provider.dart';
import 'package:pi_frame/features/workspace/workspace_pane.dart';
import 'package:pi_frame/features/workspace/workspace_pane_header.dart';
import 'package:pi_frame/ui/frame_icon_action.dart';
import 'package:pi_frame/ui/frame_pane_header.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Widget _host(double width, Widget child) => MaterialApp(
  theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

Widget _repositoryHeader() => Builder(
  builder: (context) => workspacePaneHeader(
    context,
    'Repository',
    Icons.folder_outlined,
    companionTabLabels: const <WorkspacePane, String>{},
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final icon in [
          Icons.terminal_outlined,
          Icons.more_horiz_outlined,
          Icons.refresh_outlined,
          Icons.chevron_left_outlined,
        ])
          FrameIconAction(icon: icon, tooltip: icon.codePoint.toString(), onPressed: () {}),
      ],
    ),
  ),
);

void main() {
  group('Repository pane header', () {
    final title = find.byKey(const ValueKey('workspace-pane-header-title'));
    final actions = find.byKey(const ValueKey('workspace-pane-header-actions'));

    testWidgets('keeps title and buttons on one line when wide', (tester) async {
      await tester.pumpWidget(_host(400, _repositoryHeader()));
      expect(tester.takeException(), isNull);
      expect(tester.getCenter(actions).dy, moreOrLessEquals(tester.getCenter(title).dy, epsilon: 1));
      expect(find.text('REPOSITORY'), findsOneWidget);
    });

    testWidgets('moves the buttons under a readable title when narrow', (tester) async {
      // A half-width window's Repository pane. Test fonts are wider than the
      // app's (every glyph is a full em), so this is narrower than it looks.
      await tester.pumpWidget(_host(200, _repositoryHeader()));
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(actions).dy, greaterThan(tester.getBottomLeft(title).dy - 1));
      final text = tester.renderObject<RenderParagraph>(find.text('REPOSITORY'));
      expect(text.didExceedMaxLines, isFalse, reason: 'the title is not cut off');
      expect(find.byType(FrameIconAction).hitTestable(), findsNWidgets(4));
    });

    testWidgets('never overflows, even narrower than its buttons', (tester) async {
      await tester.pumpWidget(_host(110, _repositoryHeader()));
      expect(tester.takeException(), isNull);
    });
  });

  group('Pane header actions on their own line', () {
    Widget header({required bool ownLine}) => FramePaneHeader(
      title: 'Workspace implementation',
      actionsOnOwnLine: ownLine,
      actions: const [SizedBox(key: ValueKey('chip'), width: 300, height: 24)],
    );

    testWidgets('inline by default, under the title when asked', (tester) async {
      await tester.pumpWidget(_host(900, header(ownLine: false)));
      final titleY = tester.getCenter(find.text('Workspace implementation')).dy;
      expect(tester.getCenter(find.byKey(const ValueKey('chip'))).dy, moreOrLessEquals(titleY, epsilon: 2));
      expect(find.byKey(const ValueKey('pane-header-actions-line')), findsNothing);

      await tester.pumpWidget(_host(520, header(ownLine: true)));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('pane-header-actions-line')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('chip'))).dy,
        greaterThan(tester.getBottomLeft(find.text('Workspace implementation')).dy - 1),
      );
    });
  });

  test('agent durations ignore missing timestamps', () {
    const now = 1795000000000;
    expect(formatAgentElapsed(now - 8000, now), '8s');
    expect(formatAgentElapsed(now - 185000, null, now: now), '3m 05s');
    expect(formatAgentElapsed(0, now), '', reason: 'a start restored without a timestamp');
    expect(formatAgentElapsed(now - 1000, 0), '');
    expect(formatAgentElapsed(null, now), '');
  });

  test('a running agent quiet for 10 minutes or more is flagged as possibly stuck', () {
    const now = 1795000000000;
    SubagentItem agent(String status, int quietMs) =>
        SubagentItem(id: 'a', name: 'a', status: status, updatedAt: now - quietMs);
    expect(quietMinutes(agent('running', 9 * 60000), now: now), isNull);
    expect(quietMinutes(agent('running', 52 * 60000), now: now), 52);
    expect(quietMinutes(agent('completed', 52 * 60000), now: now), isNull);
  });
}
