import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/frame_status_tag.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Widget _host(Widget child, {double width = 400}) {
  return MaterialApp(
    theme: ThemeData(extensions: const [FrameTokens.dark]),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

Color _dotColor(WidgetTester tester, Key tag) {
  final dot = tester.widget<DecoratedBox>(
    find.descendant(of: find.byKey(tag), matching: find.byType(DecoratedBox)),
  );
  return (dot.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('each tone maps to its semantic colour token', (tester) async {
    final tokens = FrameTokens.dark;
    final cases = {
      FrameStatusTone.neutral: tokens.textMuted,
      FrameStatusTone.info: tokens.info,
      FrameStatusTone.success: tokens.success,
      FrameStatusTone.warning: tokens.warning,
      FrameStatusTone.danger: tokens.danger,
    };

    for (final entry in cases.entries) {
      final key = ValueKey('tag-${entry.key.name}');
      await tester.pumpWidget(
        _host(FrameStatusTag(key: key, label: 'Attivo', tone: entry.key)),
      );
      expect(_dotColor(tester, key), entry.value, reason: entry.key.name);
      expect(find.text('Attivo'), findsOneWidget);
    }
  });

  testWidgets('tag is intrinsic and never takes the full width', (
    tester,
  ) async {
    const key = ValueKey('tag');
    await tester.pumpWidget(
      _host(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FrameStatusTag(
              key: key,
              label: "Attivo",
              tone: FrameStatusTone.success,
            ),
          ],
        ),
        width: 400,
      ),
    );

    final width = tester.getSize(find.byKey(key)).width;
    expect(width < 200, isTrue, reason: 'tag width $width');
  });

  testWidgets('default tone is neutral', (tester) async {
    const key = ValueKey('default-tag');
    await tester.pumpWidget(
      _host(const FrameStatusTag(key: key, label: 'Bozza')),
    );
    expect(_dotColor(tester, key), FrameTokens.dark.textMuted);
  });
}
