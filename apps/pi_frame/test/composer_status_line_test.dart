import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/composer/composer_status_line.dart';
import 'package:pi_frame/ui/motion.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Widget _host({required bool active, int? startedAt, bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
      home: Scaffold(
        body: Column(
          children: [
            ComposerRunStatusLine(
              active: active,
              startedAt: startedAt,
              label: 'L\'agente sta rispondendo…',
              interruptLabel: 'Interrompi',
              onInterrupt: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('ComposerRunStatusLine (plan 4.3)', () {
    testWidgets('idle takes no height', (tester) async {
      await tester.pumpWidget(_host(active: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-status-line')), findsNothing);
      expect(tester.getSize(find.byKey(const ValueKey('composer-status-idle'))).height, 0);
    });

    testWidgets('running line is 28 px tall with label, elapsed time and Interrompi', (tester) async {
      final started = DateTime.now().millisecondsSinceEpoch - 65000;
      await tester.pumpWidget(_host(active: true, startedAt: started));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('composer-status-line'))).height, 28);
      expect(find.text('L\'agente sta rispondendo…'), findsOneWidget);
      expect(find.text('Interrompi'), findsOneWidget);
      expect(find.text('1:05'), findsOneWidget);
    });

    testWidgets('enters with a fade and a 4 px rise over the small token', (tester) async {
      await tester.pumpWidget(_host(active: false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(active: true));
      final statusEl = tester.element(find.byKey(const ValueKey('composer-status-line')));
      final fade = statusEl.findAncestorWidgetOfExactType<FadeTransition>()!;
      final rise = statusEl.findAncestorWidgetOfExactType<Transform>()!;
      expect(fade.opacity.value, lessThan(0.5));
      expect(rise.transform.getTranslation().y, greaterThan(0));

      await tester.pump(FrameMotion.small);
      await tester.pump();
      expect(fade.opacity.value, 1.0);
      // Widgets are snapshots: read the transform again after the frames ran.
      final settled = tester
          .element(find.byKey(const ValueKey('composer-status-line')))
          .findAncestorWidgetOfExactType<Transform>()!;
      expect(settled.transform.getTranslation().y, closeTo(0, 0.01));
    });

    testWidgets('leaves in the shorter exit token', (tester) async {
      await tester.pumpWidget(_host(active: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(active: false));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('composer-status-line')), findsOneWidget);
      await tester.pump(FrameMotion.smallExit);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-status-line')), findsNothing);
    });

    testWidgets('reduced motion cross-fades without moving', (tester) async {
      await tester.pumpWidget(_host(active: false, disableAnimations: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(active: true, disableAnimations: true));
      final statusEl = tester.element(find.byKey(const ValueKey('composer-status-line')));
      final rise = statusEl.findAncestorWidgetOfExactType<Transform>();
      expect(rise == null || rise.transform.getTranslation().y == 0, isTrue);
      await tester.pumpAndSettle();
    });

    test('elapsed formats as m:ss, then h:mm:ss from one hour', () {
      expect(formatRunElapsed(const Duration(seconds: 5)), '0:05');
      expect(formatRunElapsed(const Duration(minutes: 12, seconds: 7)), '12:07');
      expect(formatRunElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(formatRunElapsed(const Duration(seconds: -4)), '0:00');
    });
  });
}
