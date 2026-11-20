import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/frame_snack_bar.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  testWidgets('FrameSnackBar displays in bottom-right with constrained width and dismisses on click', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    late BuildContext capturedContext;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const Center(child: Text('Test Page'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Show snackbar
    FrameSnackBar.show(capturedContext, message: 'Operazione completata con successo!');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final snackBarFinder = find.byType(SnackBar);
    expect(snackBarFinder, findsOneWidget);

    // Verify the visible Material card is constrained and positioned in the bottom-right
    final materialFinder = find.descendant(of: snackBarFinder, matching: find.byType(Material));
    expect(materialFinder, findsOneWidget);

    final cardBox = tester.getRect(materialFinder);
    expect(cardBox.width, greaterThanOrEqualTo(FrameSnackBar.minWidth));
    expect(cardBox.width, lessThanOrEqualTo(FrameSnackBar.maxWidth));
    expect(cardBox.right, equals(1920.0 - FrameSnackBar.rightOffset));

    // Click anywhere on the snackbar card
    await tester.tap(find.text('Operazione completata con successo!'));
    await tester.pumpAndSettle();

    // SnackBar should have dismissed immediately
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('FrameSnackBar action button executes callback and dismisses', (tester) async {
    var actionTriggered = false;
    late BuildContext capturedContext;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const Center(child: Text('Action Page'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    FrameSnackBar.show(
      capturedContext,
      message: 'Modifica effettuata',
      action: SnackBarAction(label: 'Annulla', onPressed: () => actionTriggered = true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Annulla'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(actionTriggered, isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const Center(child: Text('Host'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return capturedContext;
  }

  testWidgets('a success message dismisses itself after 4 s', (tester) async {
    final context = await pumpHost(tester);
    FrameSnackBar.show(context, message: 'Salvato');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SnackBar), findsOneWidget);

    // Step in frames, as a running app would, so the timer and the exit
    // animation both get frames.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('an error stays until its close control is used', (tester) async {
    final context = await pumpHost(tester);
    FrameSnackBar.show(context, message: 'Invio non riuscito', isError: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the card is an InkWell control that runs onTap and dismisses', (tester) async {
    var tapped = false;
    final context = await pumpHost(tester);
    FrameSnackBar.show(context, message: 'Copiato', onTap: () => tapped = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final card = find.byKey(const ValueKey('frame-snack-bar-card'));
    expect(card, findsOneWidget);
    await tester.tap(find.text('Copiato'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });
}
