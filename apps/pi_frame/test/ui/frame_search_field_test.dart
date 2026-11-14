import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/ui/frame_search_field.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  const strings = AppStrings(AppLanguage.it);

  late TextEditingController controller;
  late FocusNode focusNode;
  late List<String> changes;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
    changes = <String>[];
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pumpField(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: FrameSearchField(
                keyPrefix: 's',
                strings: strings,
                controller: controller,
                focusNode: focusNode,
                hintText: 'Cerca',
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('field is 32 px high', (tester) async {
    await pumpField(tester);
    expect(tester.getSize(find.byKey(const ValueKey('s-field'))).height, 32);
  });

  testWidgets('clear button appears only with text and clears it', (
    tester,
  ) async {
    await pumpField(tester);
    expect(find.byKey(const ValueKey('s-clear')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('s-field')), 'pippo');
    await tester.pump();
    expect(find.byKey(const ValueKey('s-clear')), findsOneWidget);
    expect(find.byTooltip('Cancella ricerca'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('s-clear')));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(changes.last, '');
    expect(find.byKey(const ValueKey('s-clear')), findsNothing);
  });

  testWidgets('first Escape clears the text and keeps focus', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byKey(const ValueKey('s-field')), 'abc');
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('second Escape, on an empty field, removes focus', (
    tester,
  ) async {
    await pumpField(tester);
    await tester.enterText(find.byKey(const ValueKey('s-field')), 'abc');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
  });

  testWidgets('Escape on an already empty field removes focus at once', (
    tester,
  ) async {
    await pumpField(tester);
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
  });
}
