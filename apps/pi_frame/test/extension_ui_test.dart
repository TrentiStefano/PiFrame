import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/features/dialogs/extension_ui_dialog.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';

class DialogClient extends PcpClient {
  bool responded = false;
  DialogClient() : super(port: 0, token: 'test');
  @override
  Future<Map<String, dynamic>> claimUiRequest(String sessionId, String requestId) async =>
      {'state': 'completed', 'data': {'claimed': true}};
  @override
  Future<Map<String, dynamic>> respondUiRequest(String sessionId, String requestId,
      {dynamic value, bool? confirmed, bool? cancelled}) async {
    responded = confirmed == true;
    return {'state': 'completed'};
  }
}

void main() {
  testWidgets('claim reads data envelope and confirmation reaches client', (tester) async {
    final client = DialogClient();
    await tester.pumpWidget(ProviderScope(
      overrides: [pcpClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(body: Builder(builder: (context) => TextButton(
          onPressed: () => ExtensionUiDialog.show(context, sessionId: 's', request: {
            'requestId': 'ui', 'method': 'confirm', 'title': 'Confirm action', 'dialog': true,
          }),
          child: const Text('Open'),
        ))),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();
    expect(client.responded, true);
    expect(find.text('Confirm action'), findsNothing);
    client.dispose();
  });

  Widget wrapWithTheme(Widget child) {
    return ProviderScope(
      overrides: [daemonEndpointProvider.overrideWith((ref) async => null)],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const [FrameTokens.dark],
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
