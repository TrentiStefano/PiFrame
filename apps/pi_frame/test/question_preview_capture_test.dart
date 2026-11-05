import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/features/dialogs/extension_ui_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class FixtureClient extends PcpClient {
  FixtureClient() : super(port: 0, token: 'fixture');
  @override
  Future<Map<String, dynamic>> claimUiRequest(
    String sessionId,
    String requestId,
  ) async => {
    'state': 'completed',
    'data': {'claimed': true},
  };
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in ['SchibstedGrotesk', 'SourceCodePro']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final (name, size) in [
    ('wide', const Size(960, 600)),
    ('narrow', const Size(400, 600)),
  ]) {
    testWidgets('capture $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [pcpClientProvider.overrideWithValue(FixtureClient())],
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              fontFamily: 'SchibstedGrotesk',
              extensions: const [FrameTokens.dark],
            ),
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: Center(
                  child: ExtensionUiDialog(
                    sessionId: 'fixture',
                    isCard: true,
                    request: const {
                      'requestId': 'fixture',
                      'method': 'select',
                      'title':
                          '[Navigazione] Quale navigazione preferisci?\n\n'
                          '--- 1. Menu nel titolo preview ---\n```text\n┌─────────────────────┐\n│  Preferiti  ▾       │\n├─────────────────────┤\n│ 1. Ricetta 1        │\n│ 2. Ricetta 2        │\n└─────────────────────┘\n```\n\n'
                          '--- 2. Icone laterali preview ---\n```text\n┌─────────────────────┐\n│ 1 │ Ricetta 1       │\n│ 2 │ Ricetta 2       │\n└─────────────────────┘\n```',
                      'options': [
                        '1. Menu nel titolo — Scelta compatta',
                        '2. Icone laterali — Navigazione permanente',
                        '3. Type something.',
                      ],
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../../docs/design-evidence/question-preview-$name-fixture.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }, skip: Platform.environment['PIFRAME_CAPTURE_QUESTION'] != '1');
  }
}
