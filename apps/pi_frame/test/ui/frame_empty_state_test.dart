import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/frame_empty_state.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  Future<void> pumpState(WidgetTester tester, FrameEmptyState state) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
        home: Scaffold(body: state),
      ),
    );
  }

  testWidgets('renders exactly one button', (tester) async {
    await pumpState(
      tester,
      FrameEmptyState(
        keyPrefix: 'empty',
        icon: Icons.folder_open,
        title: 'Nessuna sessione',
        message: 'Crea una sessione per iniziare a lavorare.',
        actionLabel: 'Nuova sessione',
        onAction: () {},
      ),
    );

    final root = find.byKey(const ValueKey('empty'));
    expect(
      find.descendant(
        of: root,
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: root, matching: find.byType(IconButton)),
      findsNothing,
    );
  });

  testWidgets('action runs its callback', (tester) async {
    var taps = 0;
    await pumpState(
      tester,
      FrameEmptyState(
        keyPrefix: 'empty',
        icon: Icons.folder_open,
        title: 'Titolo',
        message: 'Messaggio.',
        actionLabel: 'Azione',
        onAction: () => taps++,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('empty-action')));
    expect(taps, 1);
  });

  testWidgets('a null onAction disables the button', (tester) async {
    await pumpState(
      tester,
      const FrameEmptyState(
        keyPrefix: 'empty',
        icon: Icons.folder_open,
        title: 'Titolo',
        message: 'Messaggio.',
        actionLabel: 'Azione',
      ),
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('empty-action')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('shortcut hint is shown only when given', (tester) async {
    await pumpState(
      tester,
      const FrameEmptyState(
        keyPrefix: 'with',
        icon: Icons.folder_open,
        title: 'Titolo',
        message: 'Messaggio.',
        actionLabel: 'Azione',
        shortcutHint: 'Ctrl+N',
      ),
    );
    expect(find.byKey(const ValueKey('with-shortcut')), findsOneWidget);
    expect(find.text('Ctrl+N'), findsOneWidget);

    await pumpState(
      tester,
      const FrameEmptyState(
        keyPrefix: 'without',
        icon: Icons.folder_open,
        title: 'Titolo',
        message: 'Messaggio.',
        actionLabel: 'Azione',
      ),
    );
    expect(find.byKey(const ValueKey('without-shortcut')), findsNothing);
  });
}
