import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/features/dialogs/extension_ui_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _Client extends PcpClient {
  _Client({this.claim, this.respond}) : super(port: 0, token: 'test');
  final Future<Map<String, dynamic>> Function()? claim;
  final Future<Map<String, dynamic>> Function()? respond;
  final responses = <Object?>[];

  @override
  Future<Map<String, dynamic>> claimUiRequest(String s, String r) =>
      claim?.call() ??
      Future.value({
        'state': 'completed',
        'data': {'claimed': true},
      });

  @override
  Future<Map<String, dynamic>> respondUiRequest(
    String sessionId,
    String requestId, {
    dynamic value,
    bool? confirmed,
    bool? cancelled,
  }) {
    responses.add(cancelled == true ? 'cancelled' : (value ?? confirmed));
    return respond?.call() ?? Future.value({'state': 'completed'});
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    _Client client,
    Map<String, dynamic> request, {
    VoidCallback? onDismissed,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pcpClientProvider.overrideWithValue(client)],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: Scaffold(
            // Mirrors the composer: the card sits in a vertically unconstrained Column.
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                reverse: true,
                child: ExtensionUiDialog(
                  sessionId: 's',
                  request: request,
                  isCard: true,
                  onDismissed: onDismissed,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final longSelect = {
    'requestId': 'ui',
    'method': 'select',
    'title': 'Scegli',
    'message': List.filled(
      40,
      'Riga di contesto molto lunga della domanda.',
    ).join('\n'),
    'options': List.generate(30, (i) => 'Opzione $i'),
    'dialog': true,
  };

  testWidgets('long question: answer buttons stay on screen and work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _Client();
    await mount(tester, client, longSelect);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final send = tester.getRect(find.widgetWithText(ElevatedButton, 'Invia'));
    expect(send.bottom, lessThanOrEqualTo(500));
    expect(send.top, greaterThanOrEqualTo(0));

    await tester.ensureVisible(find.text('Opzione 25'));
    await tester.tap(find.text('Opzione 25'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Invia'));
    await tester.pump();
    expect(client.responses, ['Opzione 25']);
  });

  testWidgets(
    'claim failure other than "claimed by another" does not lock the card',
    (tester) async {
      final client = _Client(
        claim: () => Future.error(StateError('Request not found')),
      );
      await mount(tester, client, longSelect);
      await tester.pumpAndSettle();
      expect(find.textContaining('Un altro client'), findsNothing);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Invia'));
      await tester.pump();
      expect(client.responses, ['Opzione 0']);
    },
  );

  testWidgets('claim still pending does not delay answering', (tester) async {
    final claim = Completer<Map<String, dynamic>>();
    final client = _Client(claim: () => claim.future);
    await mount(tester, client, longSelect);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Invia'));
    await tester.pump();
    expect(client.responses, ['Opzione 0']);
    claim.complete({
      'state': 'completed',
      'data': {'claimed': true},
    });
    await tester.pumpAndSettle();
  });

  testWidgets('claimed by another client keeps the card locked', (
    tester,
  ) async {
    final client = _Client(
      claim: () => Future.error(
        StateError('UI request already claimed by another client'),
      ),
    );
    await mount(tester, client, longSelect);
    await tester.pumpAndSettle();
    expect(find.textContaining('Un altro client'), findsOneWidget);
    final send = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Invia'),
    );
    expect(send.onPressed, isNull);
  });

  testWidgets(
    'successful answer dismisses the card without waiting for the daemon event',
    (tester) async {
      var dismissed = 0;
      final client = _Client();
      await mount(tester, client, longSelect, onDismissed: () => dismissed++);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Invia'));
      await tester.pumpAndSettle();
      expect(dismissed, 1);
    },
  );

  testWidgets(
    'answer failing with a real error keeps the card and re-enables the buttons',
    (tester) async {
      var dismissed = 0;
      final client = _Client(respond: () => Future.error(StateError('boom')));
      await mount(tester, client, longSelect, onDismissed: () => dismissed++);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Invia'));
      await tester.pumpAndSettle();
      expect(dismissed, 0);
      expect(find.textContaining('boom'), findsOneWidget);
      final send = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Invia'),
      );
      expect(send.onPressed, isNotNull);
    },
  );

  testWidgets(
    'stale request (not found on daemon) is dismissed instead of blocking chat',
    (tester) async {
      var dismissed = 0;
      final client = _Client(
        respond: () => Future.error(StateError('Request not found')),
      );
      await mount(tester, client, longSelect, onDismissed: () => dismissed++);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Annulla'));
      await tester.pumpAndSettle();
      expect(dismissed, 1);
    },
  );

  testWidgets('card is dismissed locally when the request countdown ends', (
    tester,
  ) async {
    var dismissed = 0;
    final client = _Client();
    await mount(tester, client, {
      ...longSelect,
      'timeoutMs': 2000,
    }, onDismissed: () => dismissed++);
    await tester.pump(const Duration(seconds: 3));
    expect(dismissed, 1);
  });
}
