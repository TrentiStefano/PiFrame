import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/motion/reduced_motion_settings.dart';
import 'package:pi_frame/ui/motion.dart';
import 'package:pi_frame/ui/shimmer_border.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Widget _app({required bool reduced, required Widget child}) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('ReducedMotionSettingsNotifier', () {
    test('defaults to off and persists the choice across instances', () {
      final dir = Directory.systemTemp.createTempSync('reduced-motion-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/reduced_motion_settings.json');

      final first = ReducedMotionSettingsNotifier(storageFile: file);
      expect(first.state.enabled, isFalse);

      first.setEnabled(true);
      expect(first.state.enabled, isTrue);

      final second = ReducedMotionSettingsNotifier(storageFile: file);
      expect(second.state.enabled, isTrue);

      second.setEnabled(false);
      expect(ReducedMotionSettingsNotifier(storageFile: file).state.enabled,
          isFalse);
    });

    test('ignores a corrupt or non-boolean file and stays off', () {
      final dir = Directory.systemTemp.createTempSync('reduced-motion-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/reduced_motion_settings.json')
        ..writeAsStringSync('{"enabled": "yes"');
      expect(ReducedMotionSettingsNotifier(storageFile: file).state.enabled,
          isFalse);
    });
  });

  group('FrameEnter', () {
    testWidgets('slides and fades in normal motion', (tester) async {
      await tester.pumpWidget(_app(
        reduced: false,
        child: const FrameEnter(child: SizedBox(key: ValueKey('x'), height: 10)),
      ));
      await tester.pump();
      final start = tester.widget<Transform>(find.ancestor(
        of: find.byKey(const ValueKey('x')),
        matching: find.byType(Transform),
      ));
      expect(start.transform.getTranslation().y, greaterThan(0));

      await tester.pumpAndSettle();
      final end = tester.widget<Transform>(find.ancestor(
        of: find.byKey(const ValueKey('x')),
        matching: find.byType(Transform),
      ));
      expect(end.transform.getTranslation().y, closeTo(0, 0.001));
    });

    testWidgets('never moves under reduced motion', (tester) async {
      await tester.pumpWidget(_app(
        reduced: true,
        child: const FrameEnter(child: SizedBox(key: ValueKey('x'), height: 10)),
      ));
      await tester.pump();
      final transform = tester.widget<Transform>(find.ancestor(
        of: find.byKey(const ValueKey('x')),
        matching: find.byType(Transform),
      ));
      expect(transform.transform.getTranslation().y, 0);
      await tester.pumpAndSettle();
    });
  });

  group('FrameExpandable', () {
    testWidgets('builds its child only after the first expansion',
        (tester) async {
      var builds = 0;
      Widget body(bool expanded) => _app(
            reduced: false,
            child: FrameExpandable(
              expanded: expanded,
              child: Builder(builder: (_) {
                builds++;
                return const SizedBox(key: ValueKey('body'), height: 40);
              }),
            ),
          );

      await tester.pumpWidget(body(false));
      await tester.pumpAndSettle();
      expect(builds, 0);
      expect(find.byKey(const ValueKey('body')), findsNothing);

      await tester.pumpWidget(body(true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('body')), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('body'))).height, 40);

      await tester.pumpWidget(body(false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('body')), findsNothing);
    });
  });

  group('FrameSwitcher', () {
    Widget switcher({
      required bool reduced,
      required String id,
      bool animate = true,
    }) {
      return _app(
        reduced: reduced,
        child: Align(
          alignment: Alignment.topLeft,
          child: FrameSwitcher(
            animate: animate,
            child: SizedBox(
              key: ValueKey(id),
              width: 100,
              height: 20,
              child: Text(id),
            ),
          ),
        ),
      );
    }

    double x(WidgetTester tester, String id) =>
        tester.getTopLeft(find.byKey(ValueKey(id))).dx;

    testWidgets('slides the incoming child in from +8 px in normal motion',
        (tester) async {
      await tester.pumpWidget(switcher(reduced: false, id: 'a'));
      await tester.pumpWidget(switcher(reduced: false, id: 'b'));
      await tester.pump();
      expect(x(tester, 'b'), closeTo(8, 0.001));
      // The outgoing child travels to -8 px while it fades out.
      await tester.pump(const Duration(milliseconds: 60));
      expect(x(tester, 'a'), lessThan(0));

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('a')), findsNothing);
      expect(x(tester, 'b'), closeTo(0, 0.001));
    });

    testWidgets('cross-fades without travel under reduced motion',
        (tester) async {
      await tester.pumpWidget(switcher(reduced: true, id: 'a'));
      await tester.pumpWidget(switcher(reduced: true, id: 'b'));
      await tester.pump();
      expect(x(tester, 'b'), closeTo(0, 0.001));
      await tester.pump(const Duration(milliseconds: 60));
      expect(x(tester, 'b'), closeTo(0, 0.001));
      expect(x(tester, 'a'), closeTo(0, 0.001));

      // The cross-fade is done within FrameMotion.crossFade (120 ms).
      await tester.pump(FrameMotion.crossFade);
      expect(find.byKey(const ValueKey('a')), findsNothing);
      expect(x(tester, 'b'), closeTo(0, 0.001));
    });

    testWidgets('animate false swaps at once in normal motion',
        (tester) async {
      await tester.pumpWidget(
        switcher(reduced: false, id: 'a', animate: false),
      );
      await tester.pumpWidget(
        switcher(reduced: false, id: 'b', animate: false),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('a')), findsNothing);
      expect(x(tester, 'b'), closeTo(0, 0.001));
    });

    testWidgets('animate false swaps at once under reduced motion',
        (tester) async {
      await tester.pumpWidget(
        switcher(reduced: true, id: 'a', animate: false),
      );
      await tester.pumpWidget(
        switcher(reduced: true, id: 'b', animate: false),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('a')), findsNothing);
      expect(x(tester, 'b'), closeTo(0, 0.001));
    });
  });

  group('FrameExpandable timings', () {
    Widget body({
      required bool expanded,
      required bool reduced,
      bool animate = true,
    }) =>
        _app(
          reduced: reduced,
          child: FrameExpandable(
            expanded: expanded,
            animate: animate,
            child: const SizedBox(key: ValueKey('body'), height: 40),
          ),
        );

    testWidgets('collapses in the shorter smallExit duration', (tester) async {
      await tester.pumpWidget(body(expanded: true, reduced: false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(body(expanded: false, reduced: false));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('body')), findsOneWidget);
      await tester.pump(FrameMotion.smallExit);
      expect(find.byKey(const ValueKey('body')), findsNothing);
    });

    testWidgets('collapses in one cross-fade under reduced motion',
        (tester) async {
      await tester.pumpWidget(body(expanded: true, reduced: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(body(expanded: false, reduced: true));
      await tester.pump(FrameMotion.crossFade);
      expect(find.byKey(const ValueKey('body')), findsNothing);
    });

    testWidgets('animate false applies the state at once', (tester) async {
      await tester.pumpWidget(body(expanded: false, reduced: false));
      await tester.pumpWidget(
        body(expanded: true, reduced: false, animate: false),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('body'))).height, 40);

      await tester.pumpWidget(
        body(expanded: false, reduced: false, animate: false),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('body')), findsNothing);
    });
  });

  group('ShimmerBorder', () {
    Widget ring({required bool reduced}) => _app(
          reduced: reduced,
          child: const ShimmerBorder(
            isActive: true,
            borderRadius: BorderRadius.all(Radius.circular(10)),
            child: SizedBox(width: 100, height: 40),
          ),
        );

    Finder beamOf() => find.descendant(
          of: find.byType(ShimmerBorder),
          matching: find.byType(CustomPaint),
        );

    testWidgets('is a static accent ring under reduced motion', (tester) async {
      await tester.pumpWidget(ring(reduced: true));
      expect(beamOf(), findsNothing);
      // No looping ticker: the tree settles without waiting for frames.
      await tester.pumpAndSettle();
    });

    testWidgets('draws the beam in normal motion', (tester) async {
      await tester.pumpWidget(ring(reduced: false));
      expect(beamOf(), findsOneWidget);
    });
  });
}
