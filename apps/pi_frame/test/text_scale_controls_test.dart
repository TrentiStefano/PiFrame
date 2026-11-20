import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/ui/frame_control_scale.dart';
import 'package:pi_frame/ui/frame_icon_action.dart';
import 'package:pi_frame/ui/frame_search_field.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Widget _app({required double textScale, required Widget child}) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: page!,
    ),
    home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
  );
}

void main() {
  const strings = AppStrings(AppLanguage.en);

  testWidgets('search field is not clipped at text scale 2.0', (tester) async {
    await tester.pumpWidget(
      _app(
        textScale: 2.0,
        child: FrameSearchField(
          keyPrefix: 'test-search',
          strings: strings,
          hintText: 'Search',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final height = tester.getSize(find.byKey(const ValueKey('test-search-field'))).height;
    expect(height, greaterThanOrEqualTo(32));
  });

  testWidgets('search field keeps 32 px at text scale 1.0', (tester) async {
    await tester.pumpWidget(
      _app(
        textScale: 1.0,
        child: FrameSearchField(keyPrefix: 'test-search', strings: strings),
      ),
    );
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(ConstrainedBox).first);
    expect(size.height, greaterThanOrEqualTo(32));
  });

  testWidgets('icon action scales its glyph with text scale, capped at 1.5', (tester) async {
    await tester.pumpWidget(
      _app(
        textScale: 2.0,
        child: const FrameIconAction(
          icon: Icons.refresh_outlined,
          tooltip: 'Refresh',
          onPressed: null,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(frameControlScale(tester.element(find.byType(FrameIconAction))), 1.5);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.size, FrameSize.icon * 1.5);
  });

  testWidgets('icon action is unchanged at text scale 1.0', (tester) async {
    await tester.pumpWidget(
      _app(
        textScale: 1.0,
        child: const FrameIconAction(
          icon: Icons.refresh_outlined,
          tooltip: 'Refresh',
          onPressed: null,
        ),
      ),
    );
    expect(frameControlScale(tester.element(find.byType(FrameIconAction))), 1.0);
    expect(tester.widget<Icon>(find.byType(Icon)).size, FrameSize.icon);
  });
}
