import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/domain/errors/user_facing_error.dart';
import 'package:pi_frame/ui/frame_error_callout.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  const strings = AppStrings(AppLanguage.it);

  Future<void> pumpCallout(
    WidgetTester tester, {
    required UserFacingError error,
    VoidCallback? onRetry,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
        home: Scaffold(
          body: FrameErrorCallout(
            keyPrefix: 'test-callout',
            title: 'Impossibile caricare i file',
            error: error,
            strings: strings,
            onRetry: onRetry,
          ),
        ),
      ),
    );
  }

  testWidgets('details are collapsed by default and expand to the raw text', (
    tester,
  ) async {
    await pumpCallout(
      tester,
      error: const UserFacingError(
        title: 'Daemon non raggiungibile',
        hint: 'Verifica che il daemon sia in esecuzione.',
        details: 'socket closed by peer boom-7',
        retryable: true,
      ),
      onRetry: () {},
    );

    expect(find.text('Impossibile caricare i file'), findsOneWidget);
    expect(find.text('Daemon non raggiungibile'), findsOneWidget);
    expect(find.text('Verifica che il daemon sia in esecuzione.'), findsOneWidget);
    expect(find.text('Dettagli'), findsOneWidget);
    expect(find.byKey(const ValueKey('test-callout-details')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('test-callout-details-toggle')));
    await tester.pumpAndSettle();

    final details = tester.widget<SelectableText>(
      find.byKey(const ValueKey('test-callout-details')),
    );
    expect(details.data, 'socket closed by peer boom-7');
  });

  testWidgets('Riprova appears only when the error is retryable and a callback exists', (
    tester,
  ) async {
    var retries = 0;
    await pumpCallout(
      tester,
      error: const UserFacingError(
        title: 'Operazione non riuscita',
        details: 'x',
        retryable: true,
      ),
      onRetry: () => retries++,
    );
    expect(find.byKey(const ValueKey('test-callout-retry')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('test-callout-retry')));
    expect(retries, 1);
  });

  testWidgets('no Riprova for a non-retryable error', (tester) async {
    await pumpCallout(
      tester,
      error: const UserFacingError(
        title: 'Nessun repository Git',
        details: 'not a repo',
      ),
      onRetry: () {},
    );
    expect(find.byKey(const ValueKey('test-callout-retry')), findsNothing);
  });

  testWidgets('no Riprova without a callback', (tester) async {
    await pumpCallout(
      tester,
      error: const UserFacingError(
        title: 'Operazione non riuscita',
        details: 'x',
        retryable: true,
      ),
    );
    expect(find.byKey(const ValueKey('test-callout-retry')), findsNothing);
  });
}
