import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/frame_icon_action.dart';
import 'package:pi_frame/ui/frame_pane_header.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

const _headerKey = ValueKey('pane-header');
const _actionKey = ValueKey('pane-action');

Widget _host(Widget child, {double textScale = 1, double width = 400}) {
  return MaterialApp(
    theme: ThemeData(extensions: const [FrameTokens.dark]),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: app!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('min height is 40 and grows with text scale 1.4', (tester) async {
    await tester.pumpWidget(
      _host(
        const FramePaneHeader(key: _headerKey, title: 'Sessioni'),
        textScale: 1.4,
      ),
    );
    final height = tester.getSize(find.byKey(_headerKey)).height;
    expect(height >= FrameSize.paneHeader, isTrue, reason: 'height $height');
  });

  testWidgets('title uses the pane-heading family and no card is drawn', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const FramePaneHeader(key: _headerKey, title: 'Sessioni')),
    );

    final title = tester.widget<Text>(find.text('Sessioni'));
    expect(title.style?.fontFamily, FrameTokens.dark.headingFontFamily);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('subtitle path is middle-truncated with a tooltip', (
    tester,
  ) async {
    const path = r'C:\Repos\PiFrame\wt-p2-widgets-a\apps\pi_frame\lib';
    await tester.pumpWidget(
      _host(
        const FramePaneHeader(key: _headerKey, title: 'Git', subtitle: path),
        width: 180,
      ),
    );

    expect(find.byType(Tooltip), findsOneWidget);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, path);
  });

  testWidgets('short subtitle has no tooltip', (tester) async {
    await tester.pumpWidget(
      _host(
        const FramePaneHeader(
          key: _headerKey,
          title: 'Git',
          subtitle: r'lib\main.dart',
        ),
      ),
    );
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('trailing actions and the tab strip slot are rendered', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FramePaneHeader(
          key: _headerKey,
          title: 'Sessioni',
          actions: [
            FrameIconAction(
              key: _actionKey,
              icon: Icons.refresh,
              tooltip: 'Aggiorna',
              shortcut: 'Ctrl+R',
              onPressed: () {},
            ),
          ],
          tabs: const SizedBox(key: ValueKey('tabs'), height: 28),
        ),
      ),
    );

    expect(find.byKey(_actionKey), findsOneWidget);
    expect(find.byKey(const ValueKey('tabs')), findsOneWidget);
    final headerTop = tester.getTopLeft(find.byKey(_headerKey)).dy;
    final tabsTop = tester.getTopLeft(find.byKey(const ValueKey('tabs'))).dy;
    expect(tabsTop > headerTop + FrameSize.paneHeader - 1, isTrue);
  });
}
