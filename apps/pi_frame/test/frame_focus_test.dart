import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/frame_focus.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Finder _ring() => find.byKey(const ValueKey<String>('frame-focus-ring'));

void main() {
  group('FrameFocusRing', () {
    testWidgets('shows the ring when focus arrived by keyboard', (
      tester,
    ) async {
      final node = FocusNode(debugLabel: 'ring-target');
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FrameFocusRing(
                child: Focus(
                  focusNode: node,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
            ),
          ),
        ),
      );

      // A Tab key press switches the framework to keyboard highlighting.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      node.requestFocus();
      await tester.pump();

      expect(
        FocusManager.instance.highlightMode,
        FocusHighlightMode.traditional,
      );
      expect(_ring(), findsOneWidget);
    });

    testWidgets('draws a 2 px focusRing outline', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FrameFocusRing(
                child: Focus(
                  focusNode: node,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      node.requestFocus();
      await tester.pump();

      final decoration =
          tester.widget<DecoratedBox>(_ring()).decoration as BoxDecoration;
      final border = decoration.border! as Border;
      final tokens = FrameTokens.dark;
      expect(border.top.color, tokens.focusRing);
      expect(border.top.width, FrameFocusRing.ringWidth);
      expect(FrameFocusRing.ringWidth, 2);
      expect(FrameFocusRing.ringOffset, 2);
    });

    testWidgets('is absent for pointer (mouse) focus', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FrameFocusRing(
                child: Focus(
                  focusNode: node,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
            ),
          ),
        ),
      );

      // A pointer interaction puts the framework in pointer highlighting.
      // The bare SizedBox takes no hits; the pointer event still switches the
      // framework to pointer highlighting, which is what this test checks.
      await tester.tap(find.byType(SizedBox), warnIfMissed: false);
      await tester.pump();
      node.requestFocus();
      await tester.pump();

      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      expect(_ring(), findsNothing);
    });

    testWidgets('is absent when nothing has focus', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: FrameFocusRing(child: SizedBox(width: 40, height: 40)),
            ),
          ),
        ),
      );
      expect(_ring(), findsNothing);
    });
  });

  for (final variant in ['dark', 'light']) {
    group('ThemeData focus states ($variant)', () {
      late ThemeSpec spec;
      late FrameTokens tokens;
      late ThemeData theme;

      setUp(() {
        spec = ThemeSpec.fromJson(
          jsonDecode(File('assets/themes/piframe-$variant.json').readAsStringSync())
              as Map<String, dynamic>,
        );
        tokens = spec.toTokens();
        theme = spec.toThemeData();
      });

      test('focused buttons resolve to a focusRing side and overlay', () {
        final styles = {
          'filled': theme.filledButtonTheme.style,
          'outlined': theme.outlinedButtonTheme.style,
          'text': theme.textButtonTheme.style,
          'icon': theme.iconButtonTheme.style,
        };
        for (final entry in styles.entries) {
          final style = entry.value!;
          final side = style.side!.resolve({WidgetState.focused});
          expect(side?.color, tokens.focusRing, reason: entry.key);
          expect(side?.width, 2, reason: entry.key);
          expect(
            style.overlayColor!.resolve({WidgetState.focused}),
            tokens.focusRing.withValues(alpha: 0.2),
            reason: entry.key,
          );
        }
      });

      test('focus overlay differs from the hover overlay on tabs and switches', () {
        final tabFocus = theme.tabBarTheme.overlayColor!.resolve({
          WidgetState.focused,
        });
        final tabHover = theme.tabBarTheme.overlayColor!.resolve({
          WidgetState.hovered,
        });
        expect(tabFocus, isNot(equals(tabHover)));
        expect(tabFocus, tokens.focusRing.withValues(alpha: 0.2));

        final switchFocus = theme.switchTheme.overlayColor!.resolve({
          WidgetState.focused,
        });
        expect(switchFocus, tokens.focusRing.withValues(alpha: 0.2));
      });

      test('ThemeData focusColor uses the focusRing token', () {
        expect(theme.focusColor, tokens.focusRing.withValues(alpha: 0.2));
      });

      test('switch off outline is the border token, quieter than on', () {
        final outline = theme.switchTheme.trackOutlineColor!;
        expect(outline.resolve({}), tokens.border);
        expect(outline.resolve({WidgetState.selected}), isNull);
      });
    });
  }
}
