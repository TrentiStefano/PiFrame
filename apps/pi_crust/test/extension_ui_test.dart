import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:pi_crust/features/dialogs/extension_ui_dialog.dart';

void main() {
  Widget wrapWithTheme(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const [CrustTokens.dark],
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('ExtensionUiDialog renders confirm dialog with countdown', (tester) async {
    final request = {
      'requestId': 'req_1',
      'method': 'confirm',
      'title': 'Esecuzione comando pericoloso',
      'message': 'L\'estensione desidera eseguire rm -rf su ./build. Vuoi consentirlo?',
      'timeoutMs': 30000,
      'dialog': true,
    };

    await tester.pumpWidget(
      wrapWithTheme(
        ExtensionUiDialog(
          sessionId: 's_test',
          request: request,
        ),
      ),
    );

    expect(find.text('Esecuzione comando pericoloso'), findsOneWidget);
    expect(find.textContaining('L\'estensione desidera eseguire rm -rf'), findsOneWidget);
    expect(find.text('Conferma'), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);
    expect(find.text('30s'), findsOneWidget);
  });

  testWidgets('ExtensionUiDialog renders select dialog with options', (tester) async {
    final request = {
      'requestId': 'req_2',
      'method': 'select',
      'title': 'Scegli ambiente',
      'message': 'Seleziona l\'ambiente di deployment:',
      'options': ['Development', 'Staging', 'Production'],
      'dialog': true,
    };

    await tester.pumpWidget(
      wrapWithTheme(
        ExtensionUiDialog(
          sessionId: 's_test',
          request: request,
        ),
      ),
    );

    expect(find.text('Scegli ambiente'), findsOneWidget);
    expect(find.text('Development'), findsOneWidget);
    expect(find.text('Staging'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
  });
}
