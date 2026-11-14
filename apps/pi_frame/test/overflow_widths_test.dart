import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'package:pi_frame/features/browser/browser_controller.dart';
import 'package:pi_frame/features/browser/web_browser_pane.dart';

/// Narrow widths that every companion/transcript widget must survive without
/// a RenderFlex overflow (audit P1-4, R1, R2; plan task 1.2).
const List<double> kNarrowWidths = [280, 320];

class _EmptyHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(
        '<html><head><title>Empty</title></head><body></body></html>'
            .codeUnits,
      ),
      404,
    );
  }
}

Widget _themed({required Widget child, List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('Browser companion fits narrow widths (task 1.2a)', () {
    for (final width in kNarrowWidths) {
      testWidgets('toolbar and header do not overflow at ${width.toInt()} px',
          (tester) async {
        await tester.pumpWidget(
          _themed(
            overrides: [
              browserClientProvider.overrideWithValue(_EmptyHttpClient()),
            ],
            child: SizedBox(
              width: width,
              height: 700,
              child: WebBrowserPane(
                sessionId: 'test-session',
                onCollapse: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('browser-omnibox-input')),
          findsOneWidget,
        );
      });
    }

    testWidgets('narrow companion moves home and bookmark into the toolbar menu',
        (tester) async {
      await tester.pumpWidget(
        _themed(
          overrides: [
            browserClientProvider.overrideWithValue(_EmptyHttpClient()),
          ],
          child: const SizedBox(
            width: 280,
            height: 700,
            child: WebBrowserPane(sessionId: 'test-session'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('browser-home-btn')), findsNothing);
      expect(find.byKey(const ValueKey('browser-bookmark-btn')), findsNothing);
      expect(
        find.byKey(const ValueKey('browser-toolbar-overflow-btn')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('browser-companion-overflow-btn')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide companion keeps home and bookmark in the toolbar',
        (tester) async {
      await tester.pumpWidget(
        _themed(
          overrides: [
            browserClientProvider.overrideWithValue(_EmptyHttpClient()),
          ],
          child: const SizedBox(
            width: 480,
            height: 700,
            child: WebBrowserPane(sessionId: 'test-session'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('browser-home-btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('browser-bookmark-btn')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('browser-toolbar-overflow-btn')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
