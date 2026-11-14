import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/frame_icon_action.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: const [FrameTokens.dark]),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('target is 28 x 28 and the glyph is 16 px', (tester) async {
    await tester.pumpWidget(
      _host(
        FrameIconAction(
          key: const ValueKey('refresh'),
          icon: Icons.refresh,
          tooltip: 'Aggiorna',
          onPressed: () {},
        ),
      ),
    );

    final target = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('refresh')),
        matching: find.byType(IconButton),
      ),
    );
    expect(target.width, FrameSize.hitMin);
    expect(target.height, FrameSize.hitMin);
    expect(target.width >= 28 && target.height >= 28, isTrue);

    final glyph = tester.widget<Icon>(find.byType(Icon));
    expect(glyph.size, FrameSize.icon);
    expect(glyph.size, 16);
  });

  testWidgets('semantic label equals the tooltip, with shortcut appended', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FrameIconAction(
          icon: Icons.refresh,
          tooltip: 'Aggiorna',
          shortcut: 'Ctrl+R',
          onPressed: () {},
        ),
      ),
    );

    expect(find.byTooltip('Aggiorna (Ctrl+R)'), findsOneWidget);
    expect(find.bySemanticsLabel('Aggiorna (Ctrl+R)'), findsOneWidget);
  });

  testWidgets('tooltip without shortcut is the plain label', (tester) async {
    await tester.pumpWidget(
      _host(
        FrameIconAction(icon: Icons.close, tooltip: 'Chiudi', onPressed: () {}),
      ),
    );

    expect(find.byTooltip('Chiudi'), findsOneWidget);
    expect(find.bySemanticsLabel('Chiudi'), findsOneWidget);
  });

  testWidgets('tap fires onPressed; Enter fires it from the keyboard', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        FrameIconAction(
          icon: Icons.refresh,
          tooltip: 'Aggiorna',
          onPressed: () => taps++,
        ),
      ),
    );

    await tester.tap(find.byType(IconButton));
    expect(taps, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 2);
  });

  testWidgets('disabled when onPressed is null and selected uses the accent', (
    tester,
  ) async {
    final tokens = FrameTokens.dark;
    await tester.pumpWidget(
      _host(
        const FrameIconAction(
          icon: Icons.refresh,
          tooltip: 'Aggiorna',
          onPressed: null,
        ),
      ),
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(tester.widget<Icon>(find.byType(Icon)).color, tokens.textMuted);

    await tester.pumpWidget(
      _host(
        FrameIconAction(
          icon: Icons.refresh,
          tooltip: 'Aggiorna',
          selected: true,
          onPressed: () {},
        ),
      ),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).color, tokens.accent);
  });
}
