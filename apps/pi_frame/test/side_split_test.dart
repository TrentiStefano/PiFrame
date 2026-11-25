import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/side/side_provider.dart';
import 'package:pi_frame/features/side/side_split.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Layout of the side split (plan task 10.1): 40 % share, 320 px minimum per side,
/// a 720 px chat minimum, and a full-pane view with a back button when narrower.
void main() {
  Future<ProviderContainer> pumpSplit(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Without a daemon client the open still shows the thread, so no stream is needed.
    await container.read(sideThreadFamily('parent').notifier).openSide();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 800,
                child: const SideSplit(
                  sessionId: 'parent',
                  main: SizedBox.expand(key: ValueKey('split-main')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('wide pane splits 40 % with the chat at least 720 px', (tester) async {
    await pumpSplit(tester, 1300);

    final side = tester.getSize(find.byKey(const ValueKey('side-split-panel')));
    final main = tester.getSize(find.byKey(const ValueKey('split-main')));
    expect(side.width, closeTo((1300 - kSideDividerWidth) * 0.4, 0.5));
    expect(side.width, greaterThanOrEqualTo(kSideMinWidth));
    expect(main.width, greaterThanOrEqualTo(kSideChatMinWidth));
    expect(find.byKey(const ValueKey('side-back-btn')), findsNothing);
    expect(find.byKey(const ValueKey('side-split-divider')), findsOneWidget);
  });

  testWidgets('narrow chat shows the side thread full pane with a back button', (tester) async {
    await pumpSplit(tester, 900);

    final side = tester.getSize(find.byKey(const ValueKey('side-split-panel')));
    expect(side.width, closeTo(900, 0.5));
    expect(find.byKey(const ValueKey('side-back-btn')), findsOneWidget);
  });

  testWidgets('30 repeated shows keep the split laid out with no errors', (tester) async {
    final container = await pumpSplit(tester, 1300);
    for (var i = 0; i < 30; i++) {
      container.read(sideThreadFamily('parent').notifier).togglePanel(instant: i.isEven);
      await tester.pumpAndSettle();
      if (i.isEven) {
        // Closed by the toggle: the side collapses and the chat takes the pane.
        final main = tester.getSize(find.byKey(const ValueKey('split-main')));
        expect(main.width, closeTo(1300, 0.5));
      } else {
        final side = tester.getSize(find.byKey(const ValueKey('side-split-panel')));
        final main = tester.getSize(find.byKey(const ValueKey('split-main')));
        expect(side.width, greaterThanOrEqualTo(kSideMinWidth));
        expect(main.width, greaterThanOrEqualTo(kSideChatMinWidth));
      }
      expect(tester.takeException(), isNull);
    }
  });
}
