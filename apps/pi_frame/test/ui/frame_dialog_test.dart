import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/frame_dialog.dart';
import 'package:pi_frame/ui/frame_icon_action.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  final tokens = FrameTokens.dark;

  /// Host with one button that opens [dialog]; [result] records the outcome.
  Widget host({
    required FrameDialog<String> Function() dialog,
    bool reduced = false,
    bool instant = false,
    List<String?>? results,
  }) {
    final app = MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: [tokens]),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open'),
              onPressed: () async {
                final value = await showFrameDialog<String>(
                  context: context,
                  dialog: dialog(),
                  instant: instant,
                );
                results?.add(value);
              },
              child: const Text('Apri'),
            ),
          ),
        ),
      ),
    );
    if (!reduced) return app;
    return MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: app,
    );
  }

  /// The ScaleTransition wrapping the dialog route's child, if any.
  final dialogScale = find.ancestor(
    of: find.byType(FrameDialog<String>),
    matching: find.byType(ScaleTransition),
  );

  /// The 480 px box FrameDialog caps its content at (the dialog surface).
  final dialogSurface = find.byWidgetPredicate(
    (w) => w is ConstrainedBox && w.constraints.maxWidth == 480,
  );

  FrameDialog<String> confirmDialog({
    String title = 'Scarta modifiche',
    List<FrameDialogAction<String>>? actions,
    Widget? body,
  }) {
    return FrameDialog<String>(
      title: title,
      body: body ?? const Text('Questa operazione non può essere annullata.'),
      actions: actions ??
          const [
            FrameDialogAction<String>(
              label: 'Annulla',
              role: FrameDialogActionRole.cancel,
            ),
            FrameDialogAction<String>(
              label: 'Scarta modifiche',
              role: FrameDialogActionRole.destructive,
              value: 'discard',
            ),
          ],
    );
  }

  testWidgets('action roles map to text, filled and danger-filled buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        dialog: () => FrameDialog<String>(
          title: 'Titolo',
          body: const Text('Corpo'),
          actions: const [
            FrameDialogAction<String>(
              label: 'Annulla',
              role: FrameDialogActionRole.cancel,
            ),
            FrameDialogAction<String>(
              label: 'Salva',
              role: FrameDialogActionRole.primary,
              value: 'save',
            ),
            FrameDialogAction<String>(
              label: 'Elimina',
              role: FrameDialogActionRole.destructive,
              value: 'delete',
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    expect(
      tester.widget(find.byKey(const ValueKey('frame-dialog-cancel'))),
      isA<TextButton>(),
    );
    expect(
      tester.widget(find.byKey(const ValueKey('frame-dialog-primary'))),
      isA<FilledButton>(),
    );

    final destructive = tester.widget<FilledButton>(
      find.byKey(const ValueKey('frame-dialog-destructive')),
    );
    expect(destructive, isA<FilledButton>());
    expect(
      destructive.style?.backgroundColor?.resolve(<WidgetState>{}),
      tokens.danger,
    );
  });

  testWidgets('cancel has the initial focus when a destructive action exists', (
    tester,
  ) async {
    await tester.pumpWidget(host(dialog: () => confirmDialog()));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    final focused = FocusManager.instance.primaryFocus!.context!;
    final owner = focused.findAncestorWidgetOfExactType<TextButton>();
    expect(owner?.key, const ValueKey('frame-dialog-cancel'));
  });

  testWidgets('without a destructive action, nothing forces cancel focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        dialog: () => confirmDialog(
          actions: const [
            FrameDialogAction<String>(
              label: 'Annulla',
              role: FrameDialogActionRole.cancel,
            ),
            FrameDialogAction<String>(
              label: 'OK',
              role: FrameDialogActionRole.primary,
              value: 'ok',
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      focused.findAncestorWidgetOfExactType<TextButton>()?.key,
      isNot(const ValueKey('frame-dialog-cancel')),
    );
  });

  testWidgets('pressing an action closes the dialog with its value', (
    tester,
  ) async {
    final results = <String?>[];
    await tester.pumpWidget(
      host(dialog: () => confirmDialog(), results: results),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('frame-dialog-destructive')));
    await tester.pumpAndSettle();
    expect(results, ['discard']);
    expect(find.text('Scarta modifiche'), findsNothing);
  });

  testWidgets('dialog height is capped at 80 % of the window and the body scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      host(
        dialog: () => confirmDialog(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 80; i++) Text('riga $i'),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    // The Dialog route fills the window; measure the box FrameDialog caps.
    final capped = find.byWidgetPredicate(
      (w) => w is ConstrainedBox && w.constraints.maxWidth == 480,
    );
    final size = tester.getSize(capped);
    expect(size.height, lessThanOrEqualTo(600 * 0.8 + 0.5));
    expect(size.height, greaterThan(300));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('reduced motion cross-fades without any ScaleTransition', (
    tester,
  ) async {
    await tester.pumpWidget(host(dialog: () => confirmDialog(), reduced: true));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // The home route is zoomed by the app's page transition, so scope the
    // check to the dialog itself.
    expect(dialogScale, findsNothing);
    expect(find.byType(FadeTransition), findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('default motion scales the dialog in', (tester) async {
    await tester.pumpWidget(host(dialog: () => confirmDialog()));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(dialogScale, findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('instant option shows the dialog on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(host(dialog: () => confirmDialog(), instant: true));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();

    expect(dialogScale, findsNothing);
    expect(find.text('Scarta modifiche'), findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('a single cancel action is right-aligned, not left-aligned', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        dialog: () => confirmDialog(
          actions: const [
            FrameDialogAction<String>(
              label: 'Chiudi',
              role: FrameDialogActionRole.cancel,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    final dialogRect = tester.getRect(dialogSurface);
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('frame-dialog-cancel')),
    );
    // The button sits at the dialog's content padding from the right edge.
    expect(dialogRect.right - buttonRect.right, lessThan(FrameSpace.x6 + 1));
    expect(buttonRect.left, greaterThan(dialogRect.center.dx));
  });

  testWidgets('header actions sit at the end of the title row', (
    tester,
  ) async {
    var refreshed = 0;
    await tester.pumpWidget(
      host(
        dialog: () => FrameDialog<String>(
          title: 'Istruzioni',
          body: const Text('Corpo'),
          headerActions: [
            FrameIconAction(
              key: const ValueKey('frame-dialog-refresh'),
              icon: Icons.refresh,
              tooltip: 'Aggiorna',
              onPressed: () => refreshed++,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    final titleRect = tester.getRect(find.text('Istruzioni'));
    final actionRect = tester.getRect(
      find.byKey(const ValueKey('frame-dialog-refresh')),
    );
    final dialogRect = tester.getRect(dialogSurface);
    // Same row as the title, and to its right.
    expect(actionRect.center.dy, closeTo(titleRect.center.dy, 1));
    expect(actionRect.left, greaterThan(titleRect.right));
    expect(dialogRect.right - actionRect.right, lessThan(FrameSpace.x6 + 1));

    await tester.tap(find.byKey(const ValueKey('frame-dialog-refresh')));
    await tester.pump();
    expect(refreshed, 1);
    expect(find.text('Istruzioni'), findsOneWidget);
  });
}
