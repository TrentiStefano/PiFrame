import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _NoPinsNotifier extends PinnedSessionsNotifier {
  // In memory only, so the test never rewrites the user's real pins file.
  _NoPinsNotifier() : super(const []);
}

Future<void> _pumpRail(WidgetTester tester) async {
  final sessions = [
    {
      'id': 'a1',
      'name': 'Alpha one',
      'cwd': '/repos/alpha',
      'lastActivityAt': 2000000000000,
    },
    {
      'id': 'b1',
      'name': 'Beta one',
      'cwd': '/repos/beta',
      'lastActivityAt': 1000000000000,
    },
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pcpClientProvider.overrideWithValue(null),
        pinnedSessionsProvider.overrideWith((ref) => _NoPinsNotifier()),
        sessionListProvider.overrideWith((ref) async => sessions),
        activeSessionIdProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(body: SessionsSidebar()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the most recently used repository is expanded by default', (
    tester,
  ) async {
    await _pumpRail(tester);

    expect(find.text('Alpha one'), findsOneWidget);
    expect(find.text('Beta one'), findsNothing);
  });

  testWidgets('arrow keys move, expand and collapse the rail', (tester) async {
    await _pumpRail(tester);

    // Clicking a folder focuses the rail and toggles the folder.
    await tester.tap(find.byKey(const ValueKey('session-folder:/repos/beta')));
    await tester.pumpAndSettle();
    expect(find.text('Beta one'), findsOneWidget);

    // Down moves onto the first session of the expanded folder.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    // Left on a session returns to its folder row, and left again collapses it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Beta one'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Beta one'), findsNothing);

    // Right expands it again.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Beta one'), findsOneWidget);
  });

  testWidgets('F2 on a session opens the rename dialog', (tester) async {
    await _pumpRail(tester);

    // Alpha is expanded by default: the first click collapses it, the second
    // expands it again and leaves the cursor and focus on the rail.
    await tester.tap(find.byKey(const ValueKey('session-folder:/repos/alpha')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-folder:/repos/alpha')));
    await tester.pumpAndSettle();
    // Cursor is on the folder row; down moves onto its session.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Shift+F10 on the cursor session opens its context menu', (
    tester,
  ) async {
    await _pumpRail(tester);

    expect(find.byType(PopupMenuItem<String>), findsNothing);
    await tester.tap(find.byKey(const ValueKey('session-folder:/repos/alpha')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-folder:/repos/alpha')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    // The session menu is open: its items are the session actions.
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
  });

  testWidgets('Shift+F10 on the cursor folder opens its context menu', (
    tester,
  ) async {
    await _pumpRail(tester);

    // The folder row is the cursor after a click on it.
    await tester.tap(find.byKey(const ValueKey('session-folder:/repos/alpha')));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuItem<String>), findsWidgets);
  });

  testWidgets('the cursor ring is a keyboard cue: a click does not leave it on the card', (
    tester,
  ) async {
    await _pumpRail(tester);
    final alphaTile = find.byKey(const ValueKey('session-tile-/repos/alpha-a1'));

    bool hasRing() => tester
        .widgetList<DecoratedBox>(
          find.descendant(of: alphaTile, matching: find.byType(DecoratedBox)),
        )
        .any((box) {
          final dec = box.decoration;
          return dec is BoxDecoration &&
              dec.border != null &&
              dec.border!.top.color == FrameTokens.dark.focusRing;
        });

    // Clicking a card focuses the rail but shows no keyboard ring.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    await tester.tap(find.text('Alpha one'));
    await tester.pumpAndSettle();
    expect(hasRing(), isFalse);

    // Arrow keys switch to keyboard mode and the ring follows the cursor.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(hasRing(), isTrue);
  });
}
