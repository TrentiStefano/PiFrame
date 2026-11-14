import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/frame_icon_action.dart';
import 'package:pi_frame/ui/frame_list_row.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

const _rowKey = ValueKey('row');
const _actionKey = ValueKey('row-action');

Widget _host(Widget child, {double textScale = 1, double width = 400}) {
  return MaterialApp(
    theme: ThemeData(extensions: const [FrameTokens.dark]),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: app!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

FrameListRow _row({
  Key? key = _rowKey,
  String name = 'main.dart',
  String? secondary,
  bool selected = false,
  VoidCallback? onTap,
  ValueChanged<Offset>? onSecondaryTap,
  bool withAction = true,
}) {
  return FrameListRow(
    key: key,
    name: name,
    secondary: secondary,
    selected: selected,
    onTap: onTap ?? () {},
    onSecondaryTap: onSecondaryTap,
    leading: const Icon(Icons.description, size: 16),
    trailing: const Text('M'),
    actions: withAction
        ? [
            FrameIconAction(
              key: _actionKey,
              icon: Icons.close,
              tooltip: 'Chiudi',
              onPressed: () {},
            ),
          ]
        : const [],
  );
}

double _opacityOfAction(WidgetTester tester) {
  return tester
      .widget<Opacity>(
        find.ancestor(
          of: find.byKey(_actionKey),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;
}

void main() {
  testWidgets('min height is 28 and grows with text scale 1.4', (tester) async {
    await tester.pumpWidget(_host(_row(name: 'a.dart'), textScale: 1.4));
    final height = tester.getSize(find.byKey(_rowKey)).height;
    expect(height >= FrameSize.rowList, isTrue, reason: 'height $height');

    await tester.pumpWidget(
      _host(_row(name: 'a.dart', secondary: 'lib/a.dart'), textScale: 1.4),
    );
    final taller = tester.getSize(find.byKey(_rowKey)).height;
    expect(taller >= FrameSize.rowList, isTrue);
  });

  testWidgets('actions stay in the tree, hidden until hover or focus', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_row()));

    expect(find.byKey(_actionKey), findsOneWidget);
    expect(_opacityOfAction(tester), 0);
  });

  testWidgets('hover reveals the actions', (tester) async {
    await tester.pumpWidget(_host(_row()));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byKey(_rowKey)));
    await tester.pump();

    expect(_opacityOfAction(tester), 1);
  });

  testWidgets('actions are reachable by Tab while invisible', (tester) async {
    await tester.pumpWidget(_host(_row()));
    expect(_opacityOfAction(tester), 0);

    var reached = false;
    for (var i = 0; i < 4 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      reached =
          focused?.findAncestorWidgetOfExactType<FrameIconAction>() != null;
    }

    expect(reached, isTrue);
    expect(_opacityOfAction(tester), 1);
  });

  testWidgets('Enter and Space activate the row', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(_row(onTap: () => taps++)));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(taps, 2);
  });

  testWidgets('secondary tap reports the global position', (tester) async {
    Offset? position;
    await tester.pumpWidget(_host(_row(onSecondaryTap: (p) => position = p)));

    final center = tester.getCenter(find.byKey(_rowKey));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pump();

    expect(position, isNotNull);
    expect((position! - center).distance < 1, isTrue);
  });

  testWidgets('selected state paints the selected surface', (tester) async {
    await tester.pumpWidget(_host(_row(selected: true)));

    final decoration =
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byKey(_rowKey),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, FrameTokens.dark.surfaceElevated);
  });

  testWidgets('long secondary path is middle-truncated', (tester) async {
    await tester.pumpWidget(
      _host(
        _row(
          secondary:
              r'C:\Repos\PiFrame\wt-p2-widgets-a\apps\pi_frame\lib\main.dart',
          withAction: false,
        ),
        width: 220,
      ),
    );

    expect(find.byType(Tooltip), findsOneWidget);
    expect(find.textContaining('…'), findsOneWidget);
  });
}
