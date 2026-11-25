import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/transcript/assistant_turn_frame.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Widget _app(Widget child, {double width = 1200}) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

const _bodyText = 'First line of the assistant turn';

/// Streaming turn: live timer in the meta line, no copy action yet.
AssistantTurnFrame _streamingTurn() => AssistantTurnFrame(
  label: 'Assistant',
  elapsedChip: const Text('7s', key: ValueKey('timer')),
  body: const Text(_bodyText),
);

/// The same turn once settled: final time and the copy action.
AssistantTurnFrame _settledTurn() => AssistantTurnFrame(
  label: 'Assistant',
  elapsedChip: const Text('13s', key: ValueKey('timer')),
  onCopy: () {},
  copyKey: const ValueKey('copy'),
  copyTooltip: 'Copy',
  body: const Text(_bodyText),
);

void main() {
  testWidgets('first text line sits at the same y while streaming and once settled', (tester) async {
    await tester.pumpWidget(_app(_streamingTurn()));
    final streamingY = tester.getTopLeft(find.text(_bodyText)).dy;

    await tester.pumpWidget(_app(_settledTurn()));
    await tester.pumpAndSettle();
    final settledY = tester.getTopLeft(find.text(_bodyText)).dy;

    expect(settledY, streamingY);
  });

  testWidgets('meta line is a fixed 24 px high in both states', (tester) async {
    await tester.pumpWidget(_app(_streamingTurn()));
    final streamingMeta = tester.getSize(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == kAssistantMetaLineHeight).first,
    );
    expect(streamingMeta.height, kAssistantMetaLineHeight);

    await tester.pumpWidget(_app(_settledTurn()));
    await tester.pumpAndSettle();
    final settledMeta = tester.getSize(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == kAssistantMetaLineHeight).first,
    );
    expect(settledMeta.height, kAssistantMetaLineHeight);
  });

  testWidgets('reading measure is capped at 760 px in a wide pane', (tester) async {
    await tester.pumpWidget(_app(_settledTurn(), width: 1400));
    await tester.pumpAndSettle();
    final column = tester.getSize(find.text(_bodyText));
    expect(column.width, lessThanOrEqualTo(kAssistantReadingMeasure));
    final frameLeft = tester.getTopLeft(find.byKey(const ValueKey('copy'))).dx;
    // Centred: the copy action sits in the right part of a 760 px measure
    // that is centred in 1400 px, so it is well short of the pane edge.
    expect(frameLeft, lessThan(1400 - 100));
  });

  testWidgets('copy action is hidden until hover or focus, but stays in the tree', (tester) async {
    await tester.pumpWidget(_app(_settledTurn()));
    await tester.pumpAndSettle();

    double copyOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: find.byKey(const ValueKey('copy')), matching: find.byType(AnimatedOpacity)).first,
        )
        .opacity;

    expect(find.byKey(const ValueKey('copy')), findsOneWidget);
    expect(copyOpacity(), 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text(_bodyText)));
    await tester.pumpAndSettle();
    expect(copyOpacity(), 1);

    await gesture.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(copyOpacity(), 0);

    // Keyboard path: the action is an enabled, focusable button even while
    // it is faded out, so Tab still reaches it.
    final button = tester.widget<IconButton>(find.byKey(const ValueKey('copy')));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('copy hit target is 28 px and the meta line stays 24 px', (tester) async {
    var copied = 0;
    await tester.pumpWidget(
      _app(
        AssistantTurnFrame(
          label: 'Assistant',
          onCopy: () => copied++,
          copyKey: const ValueKey('copy'),
          copyTooltip: 'Copy',
          body: const Text(_bodyText),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.getSize(find.byKey(const ValueKey('copy')));
    expect(button.width >= 28, isTrue, reason: 'width ${button.width}');
    expect(button.height >= 28, isTrue, reason: 'height ${button.height}');

    final metaLine = tester.getSize(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == kAssistantMetaLineHeight).first,
    );
    expect(metaLine.height, kAssistantMetaLineHeight);

    // 13 px above the button centre is outside the 24 px row but inside the
    // 28 px target, so it must still press the button.
    final center = tester.getCenter(find.byKey(const ValueKey('copy')));
    await tester.tapAt(Offset(center.dx, center.dy - 13));
    await tester.pump();
    expect(copied, 1);
  });
}
