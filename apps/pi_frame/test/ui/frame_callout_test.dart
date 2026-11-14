import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/ui/frame_callout.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  const strings = AppStrings(AppLanguage.it);

  Future<void> pumpCallout(WidgetTester tester, FrameCallout callout) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
        home: Scaffold(body: callout),
      ),
    );
  }

  testWidgets('details stay collapsed until the Dettagli toggle is pressed', (
    tester,
  ) async {
    await pumpCallout(
      tester,
      const FrameCallout(
        keyPrefix: 'c1',
        tone: FrameCalloutTone.danger,
        title: 'Operazione non riuscita',
        body: Text('Riprova tra poco.'),
        details: 'socket closed by peer boom-7',
        strings: strings,
      ),
    );

    expect(find.text('Operazione non riuscita'), findsOneWidget);
    expect(find.text('Riprova tra poco.'), findsOneWidget);
    expect(find.text('Dettagli'), findsOneWidget);

    // Collapsed by default: the text is not built until the first expansion.
    expect(find.byKey(const ValueKey('c1-details')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('c1-details-toggle')));
    await tester.pumpAndSettle();

    final details = tester.widget<SelectableText>(
      find.byKey(const ValueKey('c1-details')),
    );
    expect(details.data, 'socket closed by peer boom-7');
  });

  testWidgets('no disclosure is shown without details', (tester) async {
    await pumpCallout(
      tester,
      const FrameCallout(keyPrefix: 'c2', title: 'Titolo', strings: strings),
    );
    expect(find.byKey(const ValueKey('c2-details-toggle')), findsNothing);
    expect(find.text('Dettagli'), findsNothing);
  });

  testWidgets('action widget is rendered and keeps its own key', (
    tester,
  ) async {
    var taps = 0;
    await pumpCallout(
      tester,
      FrameCallout(
        keyPrefix: 'c3',
        tone: FrameCalloutTone.warning,
        title: 'Attenzione',
        action: OutlinedButton(
          key: const ValueKey('c3-retry'),
          onPressed: () => taps++,
          child: const Text('Riprova'),
        ),
        strings: strings,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('c3-retry')));
    expect(taps, 1);
  });

  testWidgets('each tone uses its own icon', (tester) async {
    final expected = {
      FrameCalloutTone.info: Icons.info_outline,
      FrameCalloutTone.warning: Icons.warning_amber_rounded,
      FrameCalloutTone.danger: Icons.error_outline,
    };
    for (final entry in expected.entries) {
      await pumpCallout(
        tester,
        FrameCallout(
          keyPrefix: 'tone',
          tone: entry.key,
          title: 'T',
          strings: strings,
        ),
      );
      expect(
        find.byWidgetPredicate((w) => w is Icon && w.icon == entry.value),
        findsOneWidget,
        reason: entry.key.name,
      );
    }
  });
}
